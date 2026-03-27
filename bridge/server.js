const express = require("express");
const { execFile } = require("node:child_process");
const os = require("node:os");

const HOST = "0.0.0.0";
const PORT = 18790;
const TOKEN = "REDACTED_TOKEN";
const OPENCLAW = `${os.homedir()}/.nvm/versions/node/v24.14.0/bin/openclaw`;
const MAX_MESSAGE = 4000;
const MAX_HISTORY_ITEMS = 20;
const MAX_HISTORY_CONTENT = 4000;

const app = express();
app.use(express.json({ limit: "64kb" }));

app.use((req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Headers", "Authorization, Content-Type");
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  if (req.method === "OPTIONS") return res.sendStatus(204);
  next();
});

function buildPrompt(message, history) {
  const lines = [];
  for (const item of history) {
    lines.push(`${item.role}: ${item.content}`);
  }
  lines.push(`user: ${message}`);
  return lines.join("\n");
}

function parseReply(stdout) {
  const out = String(stdout || "").trim();
  if (!out) return "";
  try {
    const parsed = JSON.parse(out);
    if (typeof parsed === "string") return parsed;
    if (parsed && typeof parsed.reply === "string") return parsed.reply;
    if (parsed && typeof parsed.message === "string") return parsed.message;
    if (parsed && typeof parsed.content === "string") return parsed.content;
  } catch (_) {}
  const lines = out.split(/\r?\n/).map((v) => v.trim()).filter(Boolean);
  return lines.length ? lines[lines.length - 1] : out;
}

function runOpenClaw(prompt) {
  return new Promise((resolve, reject) => {
    execFile(
      OPENCLAW,
      ["agent", "--agent", "main", "--message", prompt],
      { timeout: 30000, maxBuffer: 1024 * 1024 },
      (error, stdout, stderr) => {
        if (error) {
          const err = new Error("OPENCLAW_EXEC_FAILED");
          err.code = error.code;
          err.killed = error.killed;
          err.signal = error.signal;
          err.stderr = String(stderr || "").trim();
          return reject(err);
        }
        resolve(parseReply(stdout));
      }
    );
  });
}

app.post("/api/chat", async (req, res) => {
  const auth = req.headers.authorization || "";
  if (auth !== `Bearer ${TOKEN}`) {
    return res.status(401).json({ error: "Unauthorized" });
  }

  const body = req.body || {};
  const { message } = body;
  const history = Array.isArray(body.history) ? body.history : [];

  if (typeof message !== "string" || !message.trim() || message.length > MAX_MESSAGE) {
    return res.status(400).json({ error: `Invalid message (1-${MAX_MESSAGE} chars)` });
  }

  if (history.length > MAX_HISTORY_ITEMS) {
    return res.status(400).json({ error: `History too long (max ${MAX_HISTORY_ITEMS})` });
  }

  for (const item of history) {
    if (!item || (item.role !== "user" && item.role !== "assistant") || typeof item.content !== "string" || item.content.length > MAX_HISTORY_CONTENT) {
      return res.status(400).json({ error: "Invalid history format" });
    }
  }

  const prompt = buildPrompt(message.trim(), history);

  try {
    const reply = await runOpenClaw(prompt);
    if (!reply) return res.status(502).json({ error: "Empty reply from OpenClaw" });
    return res.json({ reply });
  } catch (err) {
    if (err && (err.signal === "SIGTERM" || err.code === null)) {
      return res.status(504).json({ error: "OpenClaw timeout (30s)" });
    }
    const detail = err && err.stderr ? err.stderr.slice(0, 300) : "OpenClaw execution failed";
    return res.status(502).json({ error: detail });
  }
});

const fs = require("node:fs");
const path = require("node:path");

app.get("/api/tunnel-url", (req, res) => {
  const auth = req.headers.authorization || "";
  if (auth !== `Bearer ${TOKEN}`) {
    return res.status(401).json({ error: "Unauthorized" });
  }
  const urlFile = path.join(__dirname, "tunnel-url.txt");
  try {
    const url = fs.readFileSync(urlFile, "utf-8").trim();
    return res.json({ url });
  } catch {
    return res.status(404).json({ error: "Tunnel URL not available" });
  }
});

app.listen(PORT, HOST, () => {
  console.log(`OpenClaw bridge listening on ${HOST}:${PORT}`);
});