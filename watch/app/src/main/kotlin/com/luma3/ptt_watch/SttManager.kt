package com.luma3.ptt_watch

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume

class SttManager(
    private val context: Context
) {
    private var speechRecognizer: SpeechRecognizer? = null
    private var pendingResult: ((Result<String>) -> Unit)? = null
    private var isListening = false
    private var partialText = ""
    var onPartialResult: ((String) -> Unit)? = null

    suspend fun startAndAwaitText(): Result<String> = withContext(Dispatchers.Main.immediate) {
        if (!SpeechRecognizer.isRecognitionAvailable(context)) {
            return@withContext Result.failure(IllegalStateException("STT not available"))
        }

        if (Looper.myLooper() != Looper.getMainLooper()) {
            return@withContext Result.failure(IllegalStateException("Must run on main thread"))
        }

        suspendCancellableCoroutine { continuation ->
            partialText = ""

            if (speechRecognizer == null) {
                speechRecognizer = SpeechRecognizer.createSpeechRecognizer(context)
            }

            speechRecognizer?.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) = Unit
                override fun onBeginningOfSpeech() = Unit
                override fun onRmsChanged(rmsdB: Float) = Unit
                override fun onBufferReceived(buffer: ByteArray?) = Unit
                override fun onEndOfSpeech() = Unit
                override fun onEvent(eventType: Int, params: Bundle?) = Unit

                override fun onPartialResults(partialResults: Bundle?) {
                    val text = partialResults
                        ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        ?.firstOrNull()
                        .orEmpty()
                    if (text.isNotEmpty()) {
                        partialText = text
                        onPartialResult?.invoke(text)
                    }
                }

                override fun onResults(results: Bundle?) {
                    isListening = false
                    val text = results
                        ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        ?.firstOrNull()
                        .orEmpty()
                    val finalText = text.ifEmpty { partialText }
                    if (continuation.isActive) {
                        continuation.resume(Result.success(finalText))
                    }
                }

                override fun onError(error: Int) {
                    isListening = false
                    // error 6 = NO_MATCH, 7 = NO_SPEECH — return partial if available
                    if ((error == SpeechRecognizer.ERROR_NO_MATCH || error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT) && partialText.isNotEmpty()) {
                        if (continuation.isActive) {
                            continuation.resume(Result.success(partialText))
                        }
                    } else {
                        if (continuation.isActive) {
                            continuation.resume(Result.failure(IllegalStateException("stt_error_$error")))
                        }
                    }
                }
            })

            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ko-KR")
            }

            speechRecognizer?.startListening(intent)
            isListening = true

            continuation.invokeOnCancellation {
                pendingResult = null
                if (isListening) {
                    speechRecognizer?.cancel()
                    isListening = false
                }
            }
        }
    }

    fun stopListening() {
        if (isListening) {
            speechRecognizer?.stopListening()
        }
    }

    fun release() {
        speechRecognizer?.destroy()
        speechRecognizer = null
        pendingResult = null
        onPartialResult = null
        isListening = false
    }
}
