import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../models/message_type.dart';
import '../models/tts_settings.dart';
import '../services/llm_service.dart';
import '../services/stt_service.dart';
import '../services/tts_service.dart';
import 'app_phase.dart';
import 'chat_state.dart';

final chatControllerProvider =
    StateNotifierProvider<ChatController, ChatState>((ref) => ChatController());

class ChatController extends StateNotifier<ChatState> {
  ChatController()
      : _sttService = SttService(),
        _ttsService = TtsService(),
        _llmService = LlmService(
          baseUrl: const String.fromEnvironment(
            'OPENCLAW_BASE_URL',
            defaultValue: '',
          ),
          token: const String.fromEnvironment(
            'OPENCLAW_BEARER_TOKEN',
            defaultValue: '',
          ),
        ),
        super(ChatState.initial());

  final SttService _sttService;
  final TtsService _ttsService;
  final LlmService _llmService;
  Timer? _recordingTimer;
  String? _lastFailedInput;
  bool _llmRequestCancelled = false;
  final Uuid _uuid = const Uuid();

  static const int _maxMessages = 100;
  static const int _maxAutoRetries = 2;
  static const String _sessionsKey = 'chat_sessions_v1';
  static const String _currentSessionIdKey = 'current_session_id_v1';
  static const String _legacyHistoryKey = 'chat_history_v1';
  static const String _ttsAutoPlayKey = 'tts_auto_play_v1';

  Future<void> initialize() async {
    try {
      await _loadTtsAutoPlayPreference();
      await _loadSessions();
      await _ttsService.initialize();
      final permission = await Permission.microphone.request();
      if (!permission.isGranted) {
        _setError('마이크 권한이 필요합니다.');
        return;
      }
      final available = await _sttService.initialize();
      if (!available) {
        _setError('STT 엔진을 초기화할 수 없습니다.');
        return;
      }
      state = state.copyWith(phase: AppPhase.idle, clearError: true);
    } catch (e) {
      _setError('초기화 실패: $e');
    }
  }

  void setDraft(String value) {
    state = state.copyWith(draft: value);
  }

  Future<void> sendText(String text) async {
    final normalized = text.trim();
    if (normalized.isEmpty) return;

    await _enqueueAndResolveUserMessage(
      text: normalized,
      type: MessageType.text,
    );
  }

  Future<void> toggleRecording() async {
    if (state.phase == AppPhase.recording) {
      await stopRecordingKeepDraft();
    } else {
      await startRecording();
    }
  }

  Future<void> startRecording() async {
    await _startRecording();
  }

  Future<void> stopRecordingKeepDraft() async {
    await _stopRecordingKeepDraft();
  }

  Future<void> cancelRecordingAndClearDraft() async {
    await _cancelRecordingAndClearDraft();
  }

  Future<void> setTtsAutoPlay(bool enabled) async {
    state = state.copyWith(ttsAutoPlay: enabled, clearError: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_ttsAutoPlayKey, enabled);
    if (!enabled && state.phase == AppPhase.speaking) {
      await _ttsService.stop();
      state = state.copyWith(phase: AppPhase.idle, clearError: true);
    }
  }

  Future<TtsSettings> getTtsSettings() async {
    return _ttsService.getSettings();
  }

  Future<List<String>> getTtsEngines() async {
    return _ttsService.getEngines();
  }

  Future<List<Map<String, String>>> getTtsVoices() async {
    return _ttsService.getVoices();
  }

  Future<void> updateTtsEngine(String engineName) async {
    await _ttsService.setEngine(engineName);
  }

  Future<void> updateTtsVoice({
    required String name,
    required String locale,
  }) async {
    await _ttsService.setVoice(name: name, locale: locale);
  }

  Future<void> updateSpeechRate(double rate) async {
    await _ttsService.setSpeechRate(rate);
  }

  Future<void> updatePitch(double pitch) async {
    await _ttsService.setPitch(pitch);
  }

  Future<void> previewVoice(String text) async {
    await _ttsService.stop();
    await _ttsService.speak(text);
  }

  Future<void> startNewSession() async {
    final newSession = _newEmptySession();
    final nextSessions = [newSession, ...state.sessions];
    state = state.copyWith(
      sessions: nextSessions,
      currentSessionId: newSession.id,
      messages: [],
      draft: '',
      liveTranscript: '',
      recordingElapsed: Duration.zero,
      phase: AppPhase.idle,
      clearError: true,
    );
    await _persistSessions(nextSessions, newSession.id);
  }

  Future<void> selectSession(String sessionId) async {
    final selected = state.sessions.where((session) => session.id == sessionId);
    if (selected.isEmpty) return;
    final session = selected.first;
    state = state.copyWith(
      currentSessionId: session.id,
      messages: _trimMessages(session.messages),
      draft: '',
      liveTranscript: '',
      recordingElapsed: Duration.zero,
      phase: AppPhase.idle,
      clearError: true,
    );
    await _persistSessions(state.sessions, session.id);
  }

  Future<void> deleteSession(String sessionId) async {
    var remaining =
        state.sessions.where((session) => session.id != sessionId).toList();
    if (remaining.isEmpty) {
      remaining = [_newEmptySession()];
    }
    final currentExists =
        remaining.any((session) => session.id == state.currentSessionId);
    final nextCurrentSessionId =
        currentExists ? state.currentSessionId : remaining.first.id;
    final activeSession = remaining.firstWhere(
      (session) => session.id == nextCurrentSessionId,
    );
    state = state.copyWith(
      sessions: remaining,
      currentSessionId: nextCurrentSessionId,
      messages: _trimMessages(activeSession.messages),
      draft: '',
      liveTranscript: '',
      recordingElapsed: Duration.zero,
      phase: AppPhase.idle,
      clearError: true,
    );
    await _persistSessions(remaining, nextCurrentSessionId);
  }

  Future<void> _startRecording() async {
    try {
      final permission = await Permission.microphone.request();
      if (!permission.isGranted) {
        _setError('마이크 권한이 필요합니다.');
        return;
      }

      final existingDraft = state.draft.trim();
      final prefix = existingDraft.isNotEmpty ? '$existingDraft ' : '';

      state = state.copyWith(
        phase: AppPhase.recording,
        liveTranscript: '',
        recordingElapsed: Duration.zero,
        clearError: true,
      );
      _startRecordingTimer();

      await _sttService.start(onResult: (words, finalResult) {
        state = state.copyWith(liveTranscript: words, draft: '$prefix$words');
        if (finalResult && words.trim().isNotEmpty) {
          _stopRecordingTimer();
          _autoSendAfterStt('$prefix$words'.trim());
        }
      });
    } catch (e) {
      _stopRecordingTimer();
      _setError('녹음 시작 실패: $e');
    }
  }

  Future<void> _autoSendAfterStt(String text) async {
    if (state.phase != AppPhase.recording) return;
    await _sttService.stop();
    await _enqueueAndResolveUserMessage(
      text: text,
      type: MessageType.voice,
    );
  }

  Future<void> _stopRecordingKeepDraft() async {
    try {
      _stopRecordingTimer();
      await _sttService.stop();
      state = state.copyWith(
        phase: AppPhase.idle,
        liveTranscript: '',
        recordingElapsed: Duration.zero,
        clearError: true,
      );
    } catch (e) {
      _setError('녹음 정지 실패: $e');
    }
  }

  Future<void> _cancelRecordingAndClearDraft() async {
    try {
      _stopRecordingTimer();
      await _sttService.stop();
      state = state.copyWith(
        phase: AppPhase.idle,
        liveTranscript: '',
        draft: '',
        recordingElapsed: Duration.zero,
        clearError: true,
      );
    } catch (e) {
      _setError('녹음 취소 실패: $e');
    }
  }

  Future<void> retryLastFailed() async {
    final latestInput = _lastFailedInput?.trim();
    if (latestInput == null ||
        latestInput.isEmpty ||
        state.phase != AppPhase.error) {
      return;
    }
    state = state.copyWith(phase: AppPhase.thinking, clearError: true);
    await _resolveAndSpeakReply(latestInput: latestInput);
  }

  Future<void> cancelCurrentOperation() async {
    if (state.phase == AppPhase.thinking) {
      _llmRequestCancelled = true;
      _llmService.cancelActiveRequest();
      state = state.copyWith(phase: AppPhase.idle, clearError: true);
      return;
    }
    if (state.phase == AppPhase.speaking) {
      await _ttsService.stop();
      state = state.copyWith(phase: AppPhase.idle, clearError: true);
      return;
    }
    if (state.phase == AppPhase.recording) {
      await _cancelRecordingAndClearDraft();
    }
  }

  Future<void> _enqueueAndResolveUserMessage({
    required String text,
    required MessageType type,
  }) async {
    final userMessage = _newMessage(
      role: 'user',
      text: text,
      type: type,
    );
    final nextMessages = _trimMessages([...state.messages, userMessage]);
    _lastFailedInput = text;
    state = state.copyWith(
      phase: AppPhase.thinking,
      messages: nextMessages,
      draft: '',
      liveTranscript: '',
      recordingElapsed: Duration.zero,
      clearError: true,
    );
    await _persistCurrentSessionMessages(nextMessages);
    await _resolveAndSpeakReply(latestInput: text);
  }

  Future<void> _resolveAndSpeakReply({required String latestInput}) async {
    _llmRequestCancelled = false;
    final historyWithoutCurrent =
        state.messages.take(state.messages.length - 1).toList();
    for (var attempt = 0; attempt <= _maxAutoRetries; attempt++) {
      if (_llmRequestCancelled) return;
      try {
        final reply = await _llmService.chat(
          message: latestInput,
          history: historyWithoutCurrent,
        );
        if (_llmRequestCancelled) {
          return;
        }
        final aiMessage = _newMessage(
          role: 'assistant',
          text: reply,
          type: MessageType.text,
        );
        final nextMessages = _trimMessages([...state.messages, aiMessage]);
        if (state.ttsAutoPlay) {
          state = state.copyWith(
            phase: AppPhase.speaking,
            messages: nextMessages,
            clearError: true,
          );
          await _persistCurrentSessionMessages(nextMessages);
          await _ttsService.speak(reply);
        } else {
          state = state.copyWith(
            phase: AppPhase.idle,
            messages: nextMessages,
            clearError: true,
          );
          await _persistCurrentSessionMessages(nextMessages);
        }
        state = state.copyWith(phase: AppPhase.idle, clearError: true);
        return;
      } on TimeoutException {
        if (_llmRequestCancelled) return;
        if (attempt < _maxAutoRetries) continue;
        _setError('네트워크 타임아웃(30초)입니다. 연결을 확인 후 다시 시도해 주세요.');
        return;
      } on ClientException {
        if (_llmRequestCancelled) return;
        if (attempt < _maxAutoRetries) continue;
        _setError('네트워크 연결이 없습니다. 인터넷 연결 후 다시 시도해 주세요.');
        return;
      } catch (e) {
        if (_llmRequestCancelled) {
          return;
        }
        if (attempt < _maxAutoRetries) continue;
        _setError('LLM 요청 실패: $e');
        return;
      }
    }
  }

  void _startRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.phase != AppPhase.recording) {
        timer.cancel();
        return;
      }
      state = state.copyWith(
        recordingElapsed: Duration(seconds: timer.tick),
      );
    });
  }

  void _stopRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
  }

  List<ChatMessage> _trimMessages(List<ChatMessage> messages) {
    if (messages.length <= _maxMessages) return messages;
    return messages.sublist(messages.length - _maxMessages);
  }

  Future<void> _loadTtsAutoPlayPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_ttsAutoPlayKey) ?? true;
    state = state.copyWith(ttsAutoPlay: enabled);
  }

  Future<void> _loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionsKey);
    try {
      if (raw == null || raw.isEmpty) {
        await _migrateLegacyHistoryToSession(prefs);
        if (state.sessions.isEmpty) {
          final fallbackSession = _newEmptySession();
          state = state.copyWith(
            sessions: [fallbackSession],
            currentSessionId: fallbackSession.id,
            messages: [],
          );
          await _persistSessions([fallbackSession], fallbackSession.id);
        }
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final loadedSessions = decoded
          .whereType<Map>()
          .map((item) => ChatSession.fromJson(Map<String, dynamic>.from(item)))
          .where((session) => session.id.isNotEmpty)
          .toList();
      if (loadedSessions.isEmpty) {
        final fallbackSession = _newEmptySession();
        state = state.copyWith(
          sessions: [fallbackSession],
          currentSessionId: fallbackSession.id,
          messages: [],
        );
        await _persistSessions([fallbackSession], fallbackSession.id);
        return;
      }
      final requestedCurrentId = prefs.getString(_currentSessionIdKey);
      final resolvedCurrentId = loadedSessions.any(
        (session) => session.id == requestedCurrentId,
      )
          ? requestedCurrentId!
          : loadedSessions.first.id;
      final currentSession = loadedSessions.firstWhere(
        (session) => session.id == resolvedCurrentId,
      );
      state = state.copyWith(
        sessions: loadedSessions,
        currentSessionId: resolvedCurrentId,
        messages: _trimMessages(currentSession.messages),
      );
    } catch (_) {
      await prefs.remove(_sessionsKey);
      await _migrateLegacyHistoryToSession(prefs);
      if (state.sessions.isEmpty) {
        final fallbackSession = _newEmptySession();
        state = state.copyWith(
          sessions: [fallbackSession],
          currentSessionId: fallbackSession.id,
          messages: [],
        );
        await _persistSessions([fallbackSession], fallbackSession.id);
      }
    }
  }

  Future<void> _migrateLegacyHistoryToSession(SharedPreferences prefs) async {
    final raw = prefs.getString(_legacyHistoryKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final loadedMessages = decoded
          .whereType<Map>()
          .map((item) => ChatMessage.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      final defaultSession = ChatSession(
        id: 'default',
        title: _buildSessionTitle(loadedMessages),
        createdAt: DateTime.now(),
        messages: _trimMessages(loadedMessages),
      );
      state = state.copyWith(
        sessions: [defaultSession],
        currentSessionId: defaultSession.id,
        messages: defaultSession.messages,
      );
      await _persistSessions([defaultSession], defaultSession.id);
      await prefs.remove(_legacyHistoryKey);
    } catch (_) {
      await prefs.remove(_legacyHistoryKey);
    }
  }

  Future<void> _persistCurrentSessionMessages(
      List<ChatMessage> messages) async {
    final currentSessionId = state.currentSessionId;
    if (currentSessionId.isEmpty) return;
    final nextSessions = state.sessions.map((session) {
      if (session.id != currentSessionId) return session;
      return session.copyWith(
        messages: _trimMessages(messages),
        title: _buildSessionTitle(messages),
      );
    }).toList();
    state = state.copyWith(
      sessions: nextSessions,
      messages: _trimMessages(messages),
    );
    await _persistSessions(nextSessions, currentSessionId);
  }

  Future<void> _persistSessions(
    List<ChatSession> sessions,
    String currentSessionId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _sessionsKey,
      jsonEncode(sessions.map((session) => session.toJson()).toList()),
    );
    await prefs.setString(_currentSessionIdKey, currentSessionId);
  }

  ChatSession _newEmptySession() {
    return ChatSession(
      id: _uuid.v4(),
      title: '새 세션',
      createdAt: DateTime.now(),
      messages: const [],
    );
  }

  String _buildSessionTitle(List<ChatMessage> messages) {
    final firstUserMessage = messages
        .where((message) => message.role == 'user')
        .map((message) => message.text.trim())
        .firstWhere((text) => text.isNotEmpty, orElse: () => '');
    if (firstUserMessage.isEmpty) {
      return '새 세션';
    }
    return firstUserMessage.length > 30
        ? firstUserMessage.substring(0, 30)
        : firstUserMessage;
  }

  ChatMessage _newMessage({
    required String role,
    required String text,
    required MessageType type,
  }) {
    return ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: role,
      text: text,
      timestamp: DateTime.now(),
      type: type,
    );
  }

  void _setError(String message) {
    state = state.copyWith(phase: AppPhase.error, errorMessage: message);
  }

  @override
  void dispose() {
    _stopRecordingTimer();
    _llmService.cancelActiveRequest();
    _sttService.stop();
    _ttsService.stop();
    super.dispose();
  }
}
