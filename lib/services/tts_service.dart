import 'dart:async';
import 'dart:convert';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/tts_settings.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();
  TtsSettings _settings = TtsSettings.defaults();

  Future<void> initialize() async {
    _settings = await _loadSettings();
    await _tts.awaitSpeakCompletion(true);
    if (_settings.engine.isNotEmpty) {
      await _safeRun(() => _tts.setEngine(_settings.engine));
    }
    await _tts.setLanguage('ko-KR');
    await _tts.setSpeechRate(_settings.speechRate);
    await _tts.setPitch(_settings.pitch);

    if (_settings.voiceName.isNotEmpty) {
      final voice = await _findVoiceByName(_settings.voiceName);
      if (voice != null) {
        await _safeRun(() => _tts.setVoice(voice));
      }
    }
  }

  Future<TtsSettings> getSettings() async => _settings;

  Future<void> setEngine(String engineName) async {
    await _safeRun(() => _tts.setEngine(engineName));
    _settings = _settings.copyWith(engine: engineName);
    await _persistSettings();
  }

  Future<void> setVoice({required String name, required String locale}) async {
    await _safeRun(() => _tts.setVoice({'name': name, 'locale': locale}));
    _settings = _settings.copyWith(voiceName: name);
    await _persistSettings();
  }

  Future<List<String>> getEngines() async {
    final raw = await _tts.getEngines;
    if (raw is! List) return const [];
    return raw.map((engine) => engine.toString()).toList();
  }

  Future<List<Map<String, String>>> getVoices() async {
    final raw = await _tts.getVoices;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((voice) {
          final mapped = Map<String, dynamic>.from(voice);
          final name = (mapped['name'] ?? '').toString();
          final locale = (mapped['locale'] ?? '').toString();
          return {
            'name': name,
            'locale': locale,
          };
        })
        .where((voice) {
          final locale = (voice['locale'] ?? '').toLowerCase();
          return locale.startsWith('ko') || locale.contains('ko-kr');
        })
        .where((voice) => (voice['name'] ?? '').isNotEmpty)
        .toList();
  }

  Future<void> setSpeechRate(double rate) async {
    await _tts.setSpeechRate(rate);
    _settings = _settings.copyWith(speechRate: rate);
    await _persistSettings();
  }

  Future<void> setPitch(double pitch) async {
    await _tts.setPitch(pitch);
    _settings = _settings.copyWith(pitch: pitch);
    await _persistSettings();
  }

  Future<void> speak(String text) async {
    final completer = Completer<void>();

    _tts.setCompletionHandler(() {
      if (!completer.isCompleted) completer.complete();
    });

    _tts.setErrorHandler((_) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('TTS playback failed'));
      }
    });

    await _tts.speak(text);
    await completer.future;
  }

  Future<void> stop() async {
    await _tts.stop();
  }

  Future<Map<String, String>?> _findVoiceByName(String voiceName) async {
    final voices = await getVoices();
    for (final voice in voices) {
      if (voice['name'] == voiceName) return voice;
    }
    return null;
  }

  Future<TtsSettings> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(TtsSettings.sharedPreferencesKey);
    if (raw == null || raw.isEmpty) {
      return TtsSettings.defaults();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return TtsSettings.fromJson(decoded);
      }
      if (decoded is Map) {
        return TtsSettings.fromJson(Map<String, dynamic>.from(decoded));
      }
      return TtsSettings.defaults();
    } catch (_) {
      return TtsSettings.defaults();
    }
  }

  Future<void> _persistSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      TtsSettings.sharedPreferencesKey,
      jsonEncode(_settings.toJson()),
    );
  }

  Future<void> _safeRun(Future<dynamic> Function() action) async {
    try {
      await action();
    } catch (_) {}
  }
}
