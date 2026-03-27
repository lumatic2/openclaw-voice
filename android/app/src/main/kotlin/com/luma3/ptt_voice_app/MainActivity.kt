package com.luma3.ptt_voice_app

import android.content.Intent
import android.os.Bundle
import android.util.Log
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), MessageClient.OnMessageReceivedListener {
    private val channelName = "com.luma3.ptt/wear"
    private val statePath = "/ptt/state"
    private val togglePath = "/ptt/toggle"
    private val logTag = "WearBridge"
    private var pendingAutoRecord = false

    private lateinit var methodChannel: MethodChannel

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingAutoRecord = pendingAutoRecord || intent?.getBooleanExtra("auto_record", false) == true
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra("auto_record", false)) {
            pendingAutoRecord = true
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pushState" -> {
                    val status = call.argument<String>("status")
                    if (status.isNullOrBlank()) {
                        result.error("INVALID_STATUS", "Missing status in pushState", null)
                        return@setMethodCallHandler
                    }

                    pushStateToWear(status, result)
                }

                "consumeAutoRecord" -> {
                    result.success(pendingAutoRecord)
                    pendingAutoRecord = false
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onStart() {
        super.onStart()
        Wearable.getMessageClient(this).addListener(this)
    }

    override fun onStop() {
        Wearable.getMessageClient(this).removeListener(this)
        super.onStop()
    }

    override fun onMessageReceived(messageEvent: MessageEvent) {
        if (messageEvent.path != togglePath) return

        runOnUiThread {
            methodChannel.invokeMethod("onToggle", null)
        }
    }

    private fun pushStateToWear(status: String, result: MethodChannel.Result) {
        val putDataMapRequest = PutDataMapRequest.create(statePath).apply {
            dataMap.putString("status", status)
            dataMap.putLong("updatedAt", System.currentTimeMillis())
        }

        Wearable.getDataClient(this)
            .putDataItem(putDataMapRequest.asPutDataRequest().setUrgent())
            .addOnSuccessListener {
                result.success(null)
            }
            .addOnFailureListener { error ->
                Log.e(logTag, "Failed to push state to watch: $status", error)
                result.error("WEAR_PUSH_FAILED", error.message, null)
            }
    }
}
