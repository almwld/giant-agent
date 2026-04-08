import 'package:speech_to_text/speech_to_text.dart';

class VoiceService {
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;
  VoiceService._internal();
  
  final SpeechToText _speech = SpeechToText();
  bool _isListening = false;
  
  Future<bool> init() async {
    return await _speech.initialize();
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
      ),
    );
  }
  
  Future<void> stopListening() async {
    if (_isListening) {
      await _speech.stop();
      _isListening = false;
    }
  }
  
  bool get isListening => _isListening;
}
