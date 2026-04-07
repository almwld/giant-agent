import 'package:speech_to_text/speech_to_text.dart';

class VoiceService {
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;
  VoiceService._internal();
  
  final SpeechToText _speech = SpeechToText();
  bool _isListening = false;
  String _recognizedText = '';
  
  Future<bool> init() async {
    return await _speech.initialize();
  }
  
  Future<void> startListening(Function(String) onResult) async {
    if (_isListening) return;
    
    _isListening = true;
    await _speech.listen(
      onResult: (result) {
        _recognizedText = result.recognizedWords;
        onResult(_recognizedText);
      },
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
      ),
    );
  }
  
  Future<void> stopListening() async {
    if (!_isListening) return;
    
    await _speech.stop();
    _isListening = false;
  }
  
  bool get isListening => _isListening;
  String get recognizedText => _recognizedText;
}
