class TtsSettings {
  const TtsSettings({
    required this.engine,
    required this.voiceName,
    required this.speechRate,
    required this.pitch,
  });

  final String engine;
  final String voiceName;
  final double speechRate;
  final double pitch;

  static const String sharedPreferencesKey = 'tts_settings_v1';
  static const double defaultSpeechRate = 0.46;
  static const double defaultPitch = 1.0;

  factory TtsSettings.defaults() {
    return const TtsSettings(
      engine: '',
      voiceName: '',
      speechRate: defaultSpeechRate,
      pitch: defaultPitch,
    );
  }

  factory TtsSettings.fromJson(Map<String, dynamic> json) {
    return TtsSettings(
      engine: (json['engine'] ?? '').toString(),
      voiceName: (json['voiceName'] ?? '').toString(),
      speechRate: _parseDouble(json['speechRate'], defaultSpeechRate),
      pitch: _parseDouble(json['pitch'], defaultPitch),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'engine': engine,
      'voiceName': voiceName,
      'speechRate': speechRate,
      'pitch': pitch,
    };
  }

  TtsSettings copyWith({
    String? engine,
    String? voiceName,
    double? speechRate,
    double? pitch,
  }) {
    return TtsSettings(
      engine: engine ?? this.engine,
      voiceName: voiceName ?? this.voiceName,
      speechRate: speechRate ?? this.speechRate,
      pitch: pitch ?? this.pitch,
    );
  }

  static double _parseDouble(Object? value, double fallback) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }
}
