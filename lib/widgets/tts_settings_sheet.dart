import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tts_settings.dart';
import '../state/chat_controller.dart';

class TtsSettingsSheet extends ConsumerStatefulWidget {
  const TtsSettingsSheet({super.key});

  @override
  ConsumerState<TtsSettingsSheet> createState() => _TtsSettingsSheetState();
}

class _TtsSettingsSheetState extends ConsumerState<TtsSettingsSheet> {
  bool _isLoading = true;
  bool _isPreviewPlaying = false;
  String? _error;

  List<String> _engines = const [];
  List<Map<String, String>> _voices = const [];
  String _selectedEngine = '';
  String _selectedVoiceName = '';
  double _speechRate = TtsSettings.defaultSpeechRate;
  double _pitch = TtsSettings.defaultPitch;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final controller = ref.read(chatControllerProvider.notifier);
      final settings = await controller.getTtsSettings();
      final engines = await controller.getTtsEngines();
      final voices = await controller.getTtsVoices();
      if (!mounted) return;
      setState(() {
        _engines = engines;
        _voices = voices;
        _selectedEngine = settings.engine;
        _selectedVoiceName = settings.voiceName;
        _speechRate = settings.speechRate;
        _pitch = settings.pitch;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _onSelectEngine(String engine) async {
    final controller = ref.read(chatControllerProvider.notifier);
    await controller.updateTtsEngine(engine);
    final voices = await controller.getTtsVoices();
    if (!mounted) return;
    setState(() {
      _selectedEngine = engine;
      _voices = voices;
      if (_selectedVoiceName.isNotEmpty &&
          !_voices.any((voice) => voice['name'] == _selectedVoiceName)) {
        _selectedVoiceName = '';
      }
    });
  }

  Future<void> _onSelectVoice(Map<String, String> voice) async {
    final name = voice['name'] ?? '';
    final locale = voice['locale'] ?? '';
    if (name.isEmpty || locale.isEmpty) return;
    await ref.read(chatControllerProvider.notifier).updateTtsVoice(
          name: name,
          locale: locale,
        );
    if (!mounted) return;
    setState(() {
      _selectedVoiceName = name;
    });
  }

  Future<void> _onPreviewPressed() async {
    setState(() {
      _isPreviewPlaying = true;
    });
    try {
      await ref
          .read(chatControllerProvider.notifier)
          .previewVoice('안녕하세요, 저는 제이미예요.');
    } finally {
      if (mounted) {
        setState(() {
          _isPreviewPlaying = false;
        });
      }
    }
  }

  String _formatEngineName(String engineName) {
    final lower = engineName.toLowerCase();
    if (lower.contains('google')) return 'Google';
    if (lower.contains('samsung')) return 'Samsung';
    if (engineName.contains('.')) {
      return engineName.split('.').last;
    }
    return engineName;
  }

  String _formatVoiceName(String voiceName, int index) {
    final lower = voiceName.toLowerCase();
    if (lower.contains('local')) {
      return '한국어 음성 ${index + 1} (로컬)';
    }
    if (lower.contains('network')) {
      return '한국어 음성 ${index + 1} (네트워크)';
    }
    return '한국어 음성 ${index + 1}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SafeArea(
        child: SizedBox(
          height: 360,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_error != null) {
      return SafeArea(
        child: SizedBox(
          height: 360,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('설정을 불러오지 못했습니다.\n$_error'),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.82,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text(
              '음성 설정',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              'TTS 엔진',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (_engines.isEmpty)
              const Text('사용 가능한 엔진이 없습니다.')
            else
              ..._engines.map((engine) {
                final selected = engine == _selectedEngine;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(_formatEngineName(engine)),
                  subtitle: Text(engine),
                  trailing: selected ? const Icon(Icons.check) : null,
                  onTap: () => _onSelectEngine(engine),
                );
              }),
            const SizedBox(height: 12),
            Text(
              '한국어 음성',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (_voices.isEmpty)
              const Text('선택 가능한 한국어 음성이 없습니다.')
            else
              ..._voices.asMap().entries.map((entry) {
                final index = entry.key;
                final voice = entry.value;
                final name = voice['name'] ?? '';
                final selected = name == _selectedVoiceName;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(_formatVoiceName(name, index)),
                  subtitle: Text(name),
                  trailing: selected ? const Icon(Icons.check) : null,
                  onTap: () => _onSelectVoice(voice),
                );
              }),
            const SizedBox(height: 12),
            Text(
              '속도 (${_speechRate.toStringAsFixed(2)})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Slider(
              value: _speechRate.clamp(0.25, 2.0),
              min: 0.25,
              max: 2.0,
              divisions: 35,
              onChanged: (value) {
                setState(() {
                  _speechRate = value;
                });
              },
              onChangeEnd: (value) async {
                await ref
                    .read(chatControllerProvider.notifier)
                    .updateSpeechRate(value);
              },
            ),
            Text(
              '음높이 (${_pitch.toStringAsFixed(2)})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Slider(
              value: _pitch.clamp(0.5, 2.0),
              min: 0.5,
              max: 2.0,
              divisions: 30,
              onChanged: (value) {
                setState(() {
                  _pitch = value;
                });
              },
              onChangeEnd: (value) async {
                await ref
                    .read(chatControllerProvider.notifier)
                    .updatePitch(value);
              },
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _isPreviewPlaying ? null : _onPreviewPressed,
              icon: const Icon(Icons.play_arrow),
              label: Text(_isPreviewPlaying ? '재생 중...' : '미리듣기'),
            ),
          ],
        ),
      ),
    );
  }
}
