package com.luma3.ptt_watch

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject

object BridgeConfig {
    const val AUTH_TOKEN = "REDACTED_TOKEN"
    const val FALLBACK_URL = "https://were-deals-grocery-audit.trycloudflare.com/api/chat"
    private const val PREFS_NAME = "ptt_bridge"
    private const val KEY_URL = "chat_url"

    fun getSavedUrl(context: Context): String {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_URL, FALLBACK_URL) ?: FALLBACK_URL
    }

    fun saveUrl(context: Context, url: String) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putString(KEY_URL, url).apply()
    }
}

class BridgeClient(
    private val context: Context,
    private val httpClient: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, java.util.concurrent.TimeUnit.SECONDS)
        .readTimeout(60, java.util.concurrent.TimeUnit.SECONDS)
        .writeTimeout(15, java.util.concurrent.TimeUnit.SECONDS)
        .build()
) {
    suspend fun sendMessage(message: String): Result<String> = withContext(Dispatchers.IO) {
        runCatching {
            val url = BridgeConfig.getSavedUrl(context)

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
                if (!response.isSuccessful) {
                    error("http_${response.code}")
                }

                val body = response.body?.string().orEmpty()
                JSONObject(body).optString("reply").takeIf { it.isNotBlank() }
                    ?: error("invalid_reply")
            }
        }
    }
}
