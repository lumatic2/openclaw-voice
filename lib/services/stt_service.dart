import 'package:speech_to_text/speech_to_text.dart';

class SttService {
  final SpeechToText _speech = SpeechToText();

  Future<bool> initialize() async {
    return _speech.initialize();
  }

  Future<void> start(
      {required void Function(String words, bool finalResult) onResult}) async {
    await _speech.listen(
      listenMode: ListenMode.confirmation,
      onResult: (result) {
        onResult(result.recognizedWords, result.finalResult);
      },
      cancelOnError: true,
      partialResults: true,
    );
  }

  Future<void> stop() async {
    await _speech.stop();
  }

  bool get isListening => _speech.isListening;
}
