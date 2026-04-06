import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';

class VoiceService {
  static final FlutterTts _tts = FlutterTts();
  static final AudioPlayer _player = AudioPlayer();
  
  static Future<void> speak(String text) async {
    await _tts.setLanguage('ar');
    await _tts.setPitch(1.0);
    await _tts.speak(text);
  }
  
  static Future<void> stop() async {
    await _tts.stop();
  }
  
  static Future<void> playSound(String soundName) async {
    await _player.play(AssetSource('sounds/$soundName.mp3'));
  }
}
