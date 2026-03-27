package com.luma3.ptt_watch

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject

object BridgeConfig {
    const val AUTH_TOKEN = BuildConfig.BRIDGE_AUTH_TOKEN
    const val TAILSCALE_URL = BuildConfig.TAILSCALE_URL
    const val FALLBACK_URL = BuildConfig.FALLBACK_URL
    private const val PREFS_NAME = "ptt_bridge"
    private const val KEY_URL = "chat_url"

    fun getSavedFallbackUrl(context: Context): String {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_URL, FALLBACK_URL) ?: FALLBACK_URL
    }

    fun saveFallbackUrl(context: Context, url: String) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putString(KEY_URL, url).apply()
    }
}

class BridgeClient(
    private val context: Context,
    private val httpClient: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(10, java.util.concurrent.TimeUnit.SECONDS)
        .readTimeout(60, java.util.concurrent.TimeUnit.SECONDS)
        .writeTimeout(15, java.util.concurrent.TimeUnit.SECONDS)
        .build()
) {
    suspend fun sendMessage(message: String): Result<String> = withContext(Dispatchers.IO) {
        // Try Tailscale first (via phone bluetooth)
        val tailscaleResult = tryUrl(BridgeConfig.TAILSCALE_URL, message)
        if (tailscaleResult.isSuccess) return@withContext tailscaleResult

        // Fallback to trycloudflare (direct wifi)
        val fallbackUrl = BridgeConfig.getSavedFallbackUrl(context)
        val fallbackResult = tryUrl(fallbackUrl, message)
        if (fallbackResult.isSuccess) return@withContext fallbackResult

        // Try fetching new tunnel URL via Tailscale
        val newUrl = fetchTunnelUrl()
        if (newUrl != null && newUrl != fallbackUrl) {
            BridgeConfig.saveFallbackUrl(context, newUrl)
            return@withContext tryUrl(newUrl, message)
        }

        fallbackResult
    }

    private fun tryUrl(url: String, message: String): Result<String> {
        return runCatching {
            val payload = JSONObject()
                .put("message", message)
                .put("history", JSONArray())

            val request = Request.Builder()
                .url(url)
                .header("Authorization", "Bearer ${BridgeConfig.AUTH_TOKEN}")
                .header("Content-Type", "application/json")
                .post(payload.toString().toRequestBody("application/json; charset=utf-8".toMediaType()))
                .build()

            httpClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) error("http_${response.code}")
                val body = response.body?.string().orEmpty()
                JSONObject(body).optString("reply").takeIf { it.isNotBlank() }
                    ?: error("invalid_reply")
            }
        }
    }

    private fun fetchTunnelUrl(): String? {
        return try {
            val url = BridgeConfig.TAILSCALE_URL.replace("/api/chat", "/api/tunnel-url")
            val request = Request.Builder()
                .url(url)
                .header("Authorization", "Bearer ${BridgeConfig.AUTH_TOKEN}")
                .get()
                .build()
            httpClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return null
                val tunnelBase = JSONObject(response.body?.string().orEmpty()).optString("url")
                if (tunnelBase.isNotBlank()) "$tunnelBase/api/chat" else null
            }
        } catch (_: Exception) { null }
    }
}
