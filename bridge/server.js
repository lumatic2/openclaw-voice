const express = require("express");
const { execFile, execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const HOST = "0.0.0.0";
const PORT = 18790;
const TOKEN = process.env.BRIDGE_AUTH_TOKEN || "";
const SESSION_KEY = process.env.OPENCLAW_SESSION_KEY || "";
const SESSIONS_DIR = process.env.OPENCLAW_SESSIONS_DIR ||
  path.join(process.env.HOME || "", ".openclaw/agents/main/sessions");
const TRANSCRIPTS_FILE = path.join(__dirname, "transcripts.jsonl");
const MAX_MESSAGE = 4000;

function resolveOpenClaw() {
  if (process.env.OPENCLAW_BIN) return process.env.OPENCLAW_BIN;
  try {
    return execFileSync("/usr/bin/which", ["openclaw"], { encoding: "utf8" }).trim();
  } catch (_) {}
  try {
    return execFileSync("/bin/bash", ["-lc", "command -v openclaw"], { encoding: "utf8" }).trim();
  } catch (_) {}
  throw new Error("openclaw binary not found (set OPENCLAW_BIN)");
}
const OPENCLAW = resolveOpenClaw();
console.log(`[bridge] openclaw=${OPENCLAW}`);
console.log(`[bridge] session_key=${SESSION_KEY || "(none → fallback to legacy CLI agent)"}`);
console.log(`[bridge] sessions_dir=${SESSIONS_DIR}`);

const app = express();
app.use(express.json({ limit: "64kb" }));
app.use((req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Headers", "Authorization, Content-Type");
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  if (req.method === "OPTIONS") return res.sendStatus(204);
  next();
});

function gatewayCall(method, params, timeoutMs = 60000) {
  return new Promise((resolve, reject) => {
    execFile(
      OPENCLAW,
      ["gateway", "call", method, "--timeout", String(timeoutMs), "--params", JSON.stringify(params), "--json"],
      { timeout: timeoutMs + 5000, maxBuffer: 4 * 1024 * 1024 },
      (error, stdout, stderr) => {
        if (error) {
          const err = new Error(`gateway_call_failed:${method}`);
          err.stderr = String(stderr || "").trim();
          err.stdout = String(stdout || "").trim();
          return reject(err);
        }
        try {
          resolve(JSON.parse(stdout));
        } catch (e) {
          reject(new Error(`gateway_call_parse_error:${method}`));
        }
      }
    );
  });
}

function loadSessionEntry(key) {
  const file = path.join(SESSIONS_DIR, "sessions.json");
  const data = JSON.parse(fs.readFileSync(file, "utf-8"));
  const entry = data[key];
  if (!entry || !entry.sessionId) throw new Error(`session not found: ${key}`);
  return entry;
}

function readMessages(sessionId) {
  const file = path.join(SESSIONS_DIR, `${sessionId}.jsonl`);
  if (!fs.existsSync(file)) return [];
  return fs.readFileSync(file, "utf-8")
    .split(/\r?\n/)
    .filter(Boolean)
    .map((line) => { try { return JSON.parse(line); } catch { return null; } })
    .filter(Boolean);
}

function extractAssistantText(msg) {
  if (!msg) return "";
  if (typeof msg.content === "string") return msg.content;
  if (Array.isArray(msg.content)) {
    return msg.content
      .map((c) => (typeof c === "string" ? c : c?.text || c?.content || ""))
      .filter(Boolean)
      .join("\n");
  }
  if (typeof msg.text === "string") return msg.text;
  return "";
}

function findReplyAfter(messages, baselineCount) {
  for (let i = messages.length - 1; i >= baselineCount; i--) {
    const m = messages[i];
    if (m && (m.role === "assistant" || m.type === "assistant" || m.role === "model")) {
      const text = extractAssistantText(m);
      if (text) return text.trim();
    }
  }
  return "";
}

function appendTranscript(record) {
  try {
    fs.appendFileSync(TRANSCRIPTS_FILE, JSON.stringify(record) + "\n");
  } catch (e) {
    console.error(`[bridge] transcript append failed: ${e.message}`);
  }
}

async function runViaSessionRpc(message) {
  const entry = loadSessionEntry(SESSION_KEY);
  const baseline = readMessages(entry.sessionId).length;

  const sendResp = await gatewayCall("sessions.send", {
    key: SESSION_KEY,
    message,
  }, 30000);
  const runId = sendResp?.runId;
  if (!runId) throw new Error(`sessions.send returned no runId: ${JSON.stringify(sendResp).slice(0, 200)}`);

  await gatewayCall("agent.wait", { runId, timeoutMs: 90000 }, 95000);

  // Brief settle for jsonl flush
  await new Promise((r) => setTimeout(r, 250));
  const messages = readMessages(entry.sessionId);
  const reply = findReplyAfter(messages, baseline);
  if (!reply) throw new Error("no assistant reply after run");
  return reply;
}

app.post("/api/chat", async (req, res) => {
  if ((req.headers.authorization || "") !== `Bearer ${TOKEN}`) {
    return res.status(401).json({ error: "Unauthorized" });
  }
  const message = String(req.body?.message || "").trim();
  if (!message || message.length > MAX_MESSAGE) {
    return res.status(400).json({ error: `Invalid message (1-${MAX_MESSAGE} chars)` });
  }
  if (!SESSION_KEY) {
    return res.status(500).json({ error: "OPENCLAW_SESSION_KEY not configured" });
  }

  const startedAt = Date.now();
  try {
    const reply = await runViaSessionRpc(message);
    const elapsed = Date.now() - startedAt;
    appendTranscript({ ts: new Date().toISOString(), elapsed_ms: elapsed, message, reply });
    console.log(`[bridge] turn ok in ${elapsed}ms`);
    return res.json({ reply });
  } catch (err) {
    const elapsed = Date.now() - startedAt;
    const detail = err?.stderr || err?.message || "unknown_error";
    console.error(`[bridge] turn failed in ${elapsed}ms: ${detail}`);
    appendTranscript({ ts: new Date().toISOString(), elapsed_ms: elapsed, message, error: detail.slice(0, 500) });
    return res.status(502).json({ error: detail.slice(0, 300) });
  }
});

app.get("/api/tunnel-url", (req, res) => {
  if ((req.headers.authorization || "") !== `Bearer ${TOKEN}`) {
    return res.status(401).json({ error: "Unauthorized" });
  }
  try {
    const url = fs.readFileSync(path.join(__dirname, "tunnel-url.txt"), "utf-8").trim();
    return res.json({ url });
  } catch {
    return res.status(404).json({ error: "Tunnel URL not available" });
  }
});

app.listen(PORT, HOST, () => {
  console.log(`OpenClaw bridge listening on ${HOST}:${PORT}`);
});
