import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';

class VoiceAssistant {
  static final VoiceAssistant _instance = VoiceAssistant._internal();
  factory VoiceAssistant() => _instance;
  VoiceAssistant._internal();
  
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _isListening = false;
  bool _isSpeaking = false;
  
  Future<void> init() async {
    await _speech.initialize();
    await _tts.setLanguage('ar');
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(0.5);
  }
  
  Future<void> startListening(Function(String) onResult) async {
    if (_isListening) return;
    
    _isListening = await _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          onResult(result.recognizedWords);
          _isListening = false;
        }
      },
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        cancelOnError: true,
      ),
    );
  }
  
  Future<void> stopListening() async {
    if (_isListening) {
      await _speech.stop();
      _isListening = false;
    }
  }
  
  Future<void> speak(String text) async {
    if (_isSpeaking) await stopSpeaking();
    _isSpeaking = true;
    await _tts.speak(text);
    _tts.setCompletionHandler(() {
      _isSpeaking = false;
    });
  }
  
  Future<void> stopSpeaking() async {
    await _tts.stop();
    _isSpeaking = false;
  }
  
  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;
}
