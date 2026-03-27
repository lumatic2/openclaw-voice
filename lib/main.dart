import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import 'models/chat_session.dart';
import 'services/wear_ptt_bridge.dart';
import 'state/chat_controller.dart';
import 'state/app_phase.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/splash_screen.dart';
import 'widgets/status_banner.dart';
import 'widgets/tts_settings_sheet.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var launchedFromWidgetAutoRecord = false;
  if (Platform.isAndroid) {
    try {
      const channel = MethodChannel('com.luma3.ptt/wear');
      launchedFromWidgetAutoRecord =
          await channel.invokeMethod<bool>('consumeAutoRecord') ?? false;
    } on MissingPluginException {
      launchedFromWidgetAutoRecord = false;
    }
  }
  runApp(
    ProviderScope(
      child: PttVoiceApp(
        launchedFromWidgetAutoRecord: launchedFromWidgetAutoRecord,
      ),
    ),
  );
}

class PttVoiceApp extends StatelessWidget {
  const PttVoiceApp({
    super.key,
    required this.launchedFromWidgetAutoRecord,
  });

  final bool launchedFromWidgetAutoRecord;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '제이미',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamily: 'Pretendard',
      ),
      themeMode: ThemeMode.dark,
      home: launchedFromWidgetAutoRecord
          ? const ChatScreen(autoRecordOnLaunch: true)
          : const SplashScreen(nextScreen: ChatScreen()),
    );
  }
}

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, this.autoRecordOnLaunch = false});

  final bool autoRecordOnLaunch;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final WearPttBridge _wearBridge = WearPttBridge();
  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseScale = Tween<double>(begin: 1, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseOpacity = Tween<double>(begin: 0.25, end: 0.5).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeControllers();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _wearBridge.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeControllers() async {
    final controller = ref.read(chatControllerProvider.notifier);
    await controller.initialize();
    await _wearBridge.initialize(onToggleRequested: controller.toggleRecording);
    await _wearBridge.pushState(ref.read(chatControllerProvider).phase);
    final shouldAutoRecord =
        widget.autoRecordOnLaunch || await _wearBridge.consumeAutoRecord();
    if (shouldAutoRecord) {
      await controller.startRecording();
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent + 120,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final year = dateTime.year.toString().padLeft(4, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  String _sessionPreview(ChatSession session) {
    final firstUserMessage = session.messages
        .where((message) => message.role == 'user')
        .map((message) => message.text.trim())
        .firstWhere((text) => text.isNotEmpty, orElse: () => '');
    if (firstUserMessage.isEmpty) {
      return '(메시지 없음)';
    }
    return firstUserMessage.length > 50
        ? '${firstUserMessage.substring(0, 50)}...'
        : firstUserMessage;
  }

  Future<void> _showSessionListBottomSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final state = ref.watch(chatControllerProvider);
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '세션 목록',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: state.sessions.length,
                        itemBuilder: (context, index) {
                          final session = state.sessions[index];
                          return Dismissible(
                            key: ValueKey(session.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              color: Colors.red,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: const Icon(
                                Icons.delete,
                                color: Colors.white,
                              ),
                            ),
                            onDismissed: (_) {
                              ref
                                  .read(chatControllerProvider.notifier)
                                  .deleteSession(session.id);
                              _textController.clear();
                            },
                            child: ListTile(
                              title: Text(
                                session.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${_formatDateTime(session.createdAt)}\n${_sessionPreview(session)}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              isThreeLine: true,
                              trailing: state.currentSessionId == session.id
                                  ? const Icon(Icons.check_circle)
                                  : null,
                              onTap: () {
                                ref
                                    .read(chatControllerProvider.notifier)
                                    .selectSession(session.id);
                                _textController.clear();
                                Navigator.of(context).pop();
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showTtsSettingsBottomSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const TtsSettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatControllerProvider);

    ref.listen(chatControllerProvider.select((s) => s.messages.length),
        (_, __) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    });
    ref.listen(chatControllerProvider.select((s) => s.phase), (_, next) {
      _wearBridge.pushState(next);
    });

    if (state.phase == AppPhase.recording) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
      _textController.value = _textController.value.copyWith(
        text: state.draft,
        selection: TextSelection.collapsed(offset: state.draft.length),
      );
    } else if (_pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.value = 0;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('제이미'),
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            onPressed: () {
              ref
                  .read(chatControllerProvider.notifier)
                  .setTtsAutoPlay(!state.ttsAutoPlay);
            },
            icon: Icon(
              state.ttsAutoPlay ? Icons.volume_up : Icons.volume_off,
            ),
            tooltip: state.ttsAutoPlay ? 'TTS 켜짐' : 'TTS 꺼짐',
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'new_session') {
                await ref
                    .read(chatControllerProvider.notifier)
                    .startNewSession();
                _textController.clear();
                return;
              }
              if (value == 'session_list') {
                await _showSessionListBottomSheet();
                return;
              }
              if (value == 'voice_settings') {
                await _showTtsSettingsBottomSheet();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'new_session',
                child: Text('새 세션 시작'),
              ),
              PopupMenuItem(
                value: 'session_list',
                child: Text('이전 세션 목록'),
              ),
              PopupMenuItem(
                value: 'voice_settings',
                child: Text('음성 설정'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          StatusBanner(
            phase: state.phase,
            errorMessage: state.errorMessage,
            recordingElapsed: state.recordingElapsed,
            onRetry: () =>
                ref.read(chatControllerProvider.notifier).retryLastFailed(),
            onCancel: () => ref
                .read(chatControllerProvider.notifier)
                .cancelCurrentOperation(),
          ),
          Expanded(
            child: state.messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.mic_rounded,
                            size: 64,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.42),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '마이크를 눌러\n대화를 시작하세요',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant
                                      .withValues(alpha: 0.82),
                                ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: state.messages.length,
                    itemBuilder: (context, index) {
                      final message = state.messages[index];
                      return ChatBubble(message: message);
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      enabled: state.phase != AppPhase.thinking &&
                          state.phase != AppPhase.speaking,
                      decoration: InputDecoration(
                        hintText: '메시지 입력...',
                        isDense: true,
                        filled: true,
                        fillColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                            width: 1.2,
                          ),
                        ),
                      ),
                      minLines: 1,
                      maxLines: 3,
                      onChanged: (value) => ref
                          .read(chatControllerProvider.notifier)
                          .setDraft(value),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (state.phase == AppPhase.recording) ...[
                    IconButton.filledTonal(
                      iconSize: 28,
                      constraints: const BoxConstraints.tightFor(
                        width: 56,
                        height: 56,
                      ),
                      onPressed: () async {
                        await ref
                            .read(chatControllerProvider.notifier)
                            .cancelRecordingAndClearDraft();
                        _textController.clear();
                      },
                      icon: const Icon(Icons.close),
                    ),
                    const SizedBox(width: 8),
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _pulseScale.value,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.red.withValues(
                                    alpha: _pulseOpacity.value,
                                  ),
                                  blurRadius: 14,
                                  spreadRadius: 1.5,
                                ),
                              ],
                            ),
                            child: IconButton.filled(
                              iconSize: 28,
                              constraints: const BoxConstraints.tightFor(
                                width: 56,
                                height: 56,
                              ),
                              style: IconButton.styleFrom(
                                backgroundColor:
                                    Theme.of(context).colorScheme.error,
                                foregroundColor:
                                    Theme.of(context).colorScheme.onError,
                              ),
                              onPressed: () {
                                ref
                                    .read(chatControllerProvider.notifier)
                                    .stopRecordingKeepDraft();
                              },
                              icon: const Icon(Icons.mic),
                            ),
                          ),
                        );
                      },
                    ),
                  ] else ...[
                    IconButton.filled(
                      iconSize: 28,
                      constraints: const BoxConstraints.tightFor(
                        width: 56,
                        height: 56,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.red.shade400,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: state.phase == AppPhase.thinking ||
                              state.phase == AppPhase.speaking
                          ? null
                          : () {
                              ref
                                  .read(chatControllerProvider.notifier)
                                  .startRecording();
                            },
                      icon: const Icon(Icons.mic),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      iconSize: 28,
                      constraints: const BoxConstraints.tightFor(
                        width: 56,
                        height: 56,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor:
                            Theme.of(context).colorScheme.onPrimary,
                      ),
                      onPressed: state.phase == AppPhase.thinking ||
                              state.phase == AppPhase.speaking
                          ? null
                          : () {
                              final text = _textController.text;
                              ref
                                  .read(chatControllerProvider.notifier)
                                  .sendText(text);
                              _textController.clear();
                            },
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
