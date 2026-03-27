import '../models/chat_message.dart';
import '../models/chat_session.dart';
import 'app_phase.dart';

class ChatState {
  final AppPhase phase;
  final List<ChatMessage> messages;
  final List<ChatSession> sessions;
  final String currentSessionId;
  final String draft;
  final String liveTranscript;
  final bool ttsAutoPlay;
  final String? errorMessage;
  final Duration recordingElapsed;

  const ChatState({
    required this.phase,
    required this.messages,
    required this.sessions,
    required this.currentSessionId,
    required this.draft,
    required this.liveTranscript,
    required this.ttsAutoPlay,
    required this.errorMessage,
    required this.recordingElapsed,
  });

  factory ChatState.initial() {
    return const ChatState(
      phase: AppPhase.idle,
      messages: [],
      sessions: [],
      currentSessionId: '',
      draft: '',
      liveTranscript: '',
      ttsAutoPlay: true,
      errorMessage: null,
      recordingElapsed: Duration.zero,
    );
  }

  ChatState copyWith({
    AppPhase? phase,
    List<ChatMessage>? messages,
    List<ChatSession>? sessions,
    String? currentSessionId,
    String? draft,
    String? liveTranscript,
    bool? ttsAutoPlay,
    String? errorMessage,
    Duration? recordingElapsed,
    bool clearError = false,
  }) {
    return ChatState(
      phase: phase ?? this.phase,
      messages: messages ?? this.messages,
      sessions: sessions ?? this.sessions,
      currentSessionId: currentSessionId ?? this.currentSessionId,
      draft: draft ?? this.draft,
      liveTranscript: liveTranscript ?? this.liveTranscript,
      ttsAutoPlay: ttsAutoPlay ?? this.ttsAutoPlay,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      recordingElapsed: recordingElapsed ?? this.recordingElapsed,
    );
  }
}
