import 'package:flutter_tts/flutter_tts.dart';

class TTSService {
  static final TTSService _instance = TTSService._internal();
  factory TTSService() => _instance;
  TTSService._internal();
  
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;
  
  Future<void> init() async {
    await _tts.setLanguage('ar');
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(0.5);
  }
  
  Future<void> speak(String text) async {
    if (_isSpeaking) await stop();
    _isSpeaking = true;
    await _tts.speak(text);
    _tts.setCompletionHandler(() {
      _isSpeaking = false;
    });
  }
  
  Future<void> stop() async {
    await _tts.stop();
    _isSpeaking = false;
  }
  
  bool get isSpeaking => _isSpeaking;
}
