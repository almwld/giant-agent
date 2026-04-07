import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';

class VoiceService {
  static final SpeechToText _speech = SpeechToText();
  static final FlutterTts _tts = FlutterTts();
  static bool _isListening = false;
  
  static Future<void> init() async {
    await _speech.initialize();
    await _tts.setLanguage('ar');
  }
  
  static Future<void> startListening(Function(String) onResult) async {
    if (_isListening) return;
    _isListening = await _speech.listen(onResult: (result) {
      if (result.finalResult) onResult(result.recognizedWords);
    });
  }
  
  static Future<void> stopListening() async {
    if (_isListening) await _speech.stop();
    _isListening = false;
  }
  
  static Future<void> speak(String text) async {
    await _tts.speak(text);
  }
  
  static bool get isListening => _isListening;
}
