package com.luma3.ptt_watch

import android.app.Application
import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import java.util.Locale
import kotlin.coroutines.resume

enum class PttStatus(val label: String) {
    Idle("대기"),
    Recording("녹음 중..."),
    Thinking("생각 중..."),
    Speaking("말하는 중..."),
    Error("오류")
}

data class PttUiState(
    val status: PttStatus = PttStatus.Idle,
    val lastReply: String = "대기 중",
    val partialText: String = ""
)

class PttViewModel(application: Application) : AndroidViewModel(application) {
    private val bridgeClient = BridgeClient(application.applicationContext)
    private val sttManager = SttManager(application.applicationContext)
    private val vibrator = application.applicationContext.resolveVibrator()
    private var tts: TextToSpeech? = null
    private var ttsReady = false

    init {
        tts = TextToSpeech(application.applicationContext) { status ->
            if (status == TextToSpeech.SUCCESS) {
                tts?.language = Locale.KOREAN
                ttsReady = true
            }
        }
    }

    private val _uiState = MutableStateFlow(PttUiState())
    val uiState: StateFlow<PttUiState> = _uiState.asStateFlow()

    private var sttJob: Job? = null

    fun startRecordingIfIdle() {
        if (_uiState.value.status == PttStatus.Idle || _uiState.value.status == PttStatus.Error) {
            startRecording()
        }
    }

    fun onMicTap() {
        when (_uiState.value.status) {
            PttStatus.Idle, PttStatus.Error -> startRecording()
            PttStatus.Recording -> stopRecording()
            PttStatus.Speaking -> stopSpeaking()
            PttStatus.Thinking -> Unit
        }
    }

    private fun startRecording() {
        sttJob?.cancel()
        _uiState.update { it.copy(status = PttStatus.Recording, partialText = "") }

        sttManager.onPartialResult = { text ->
            _uiState.update { it.copy(partialText = text) }
        }

        sttJob = viewModelScope.launch {
            val result = sttManager.startAndAwaitText()

            if (result.isFailure) {
                _uiState.update { it.copy(status = PttStatus.Error, lastReply = "음성 인식 실패: ${result.exceptionOrNull()?.message}") }
                vibrateError()
                return@launch
            }

            val text = result.getOrNull().orEmpty().trim()
            if (text.isEmpty()) {
                _uiState.update { it.copy(status = PttStatus.Error, lastReply = "인식된 텍스트 없음") }
                vibrateError()
                return@launch
            }

            _uiState.update { it.copy(status = PttStatus.Thinking, partialText = text) }

            val response = bridgeClient.sendMessage(text)
            if (response.isSuccess) {
                val reply = response.getOrNull().orEmpty()
                _uiState.update {
                    it.copy(
                        status = PttStatus.Speaking,
                        lastReply = reply,
                        partialText = ""
                    )
                }
                vibrateSuccess()
                speakAndAwait(reply)
                _uiState.update { it.copy(status = PttStatus.Idle) }
            } else {
                val errMsg = response.exceptionOrNull()?.message ?: "연결 실패"
                _uiState.update { it.copy(status = PttStatus.Error, lastReply = "연결 실패: $errMsg") }
                vibrateError()
            }
        }
    }

    private fun stopRecording() {
        sttManager.stopListening()
    }

    private fun stopSpeaking() {
        tts?.stop()
        _uiState.update { it.copy(status = PttStatus.Idle) }
    }

    private suspend fun speakAndAwait(text: String) {
        if (!ttsReady || text.isBlank()) return
        suspendCancellableCoroutine { continuation ->
            tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) = Unit
                override fun onDone(utteranceId: String?) {
                    if (continuation.isActive) continuation.resume(Unit)
                }
                @Deprecated("Deprecated")
                override fun onError(utteranceId: String?) {
                    if (continuation.isActive) continuation.resume(Unit)
                }
            })
            tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "ptt_reply")
            continuation.invokeOnCancellation { tts?.stop() }
        }
    }

    override fun onCleared() {
        tts?.stop()
        tts?.shutdown()
        sttManager.release()
        super.onCleared()
    }

    private fun vibrateSuccess() {
        val pattern = longArrayOf(0, 100, 80, 100)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, -1))
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(pattern, -1)
        }
    }

    private fun vibrateError() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createOneShot(120, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(120)
        }
    }
}

private fun Context.resolveVibrator(): Vibrator? {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        val manager = getSystemService(VibratorManager::class.java)
        manager?.defaultVibrator
    } else {
        @Suppress("DEPRECATION")
        getSystemService(Vibrator::class.java)
    }
}
