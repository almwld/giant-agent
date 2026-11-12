import 'package:flutter_tts/flutter_tts.dart';

/// Text-to-speech output shared by chat replies and voice conversations.
/// Arabic is preferred, while device voices remain available as a fallback.
class VoiceOutputService {
  VoiceOutputService._();
  static final VoiceOutputService instance = VoiceOutputService._();

  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  bool _speaking = false;

  bool get isSpeaking => _speaking;

  Future<void> initialize() async {
    if (_initialized) return;
    final dynamic available = await _tts.getLanguages;
    final arabicLanguages = available is List
        ? available.map((value) => value.toString())
            .where((value) => value.toLowerCase().startsWith('ar'))
            .toList()
        : <String>[];
    final arabicLocale = arabicLanguages.contains('ar-SA')
        ? 'ar-SA'
        : (arabicLanguages.isNotEmpty ? arabicLanguages.first : 'ar-SA');
    await _tts.setLanguage(arabicLocale);
    await _tts.setSpeechRate(0.48);
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(false);
    _tts.setStartHandler(() => _speaking = true);
    _tts.setCompletionHandler(() => _speaking = false);
    _tts.setCancelHandler(() => _speaking = false);
    _tts.setErrorHandler((_) => _speaking = false);
    _initialized = true;
  }

  Future<List<Map<String, dynamic>>> getAvailableVoices() async {
    await initialize();
    final dynamic available = await _tts.getVoices;
    if (available is! List) return const <Map<String, dynamic>>[];
    return available.whereType<Map>().map((voice) {
      final item = Map<String, dynamic>.from(voice);
      return <String, dynamic>{
        'name': item['name']?.toString() ?? '',
        'locale': item['locale']?.toString() ?? '',
        if (item['quality'] != null) 'quality': item['quality'],
        if (item['gender'] != null) 'gender': item['gender'],
        if (item['network_required'] != null) 'network_required': item['network_required'],
      };
    }).where((voice) => voice['name']!.toString().isNotEmpty).toList(growable: false);
  }

  Future<void> speak(
    String text, {
    bool waitForCompletion = false,
  }) async {
    final value = text.trim();
    if (value.isEmpty) return;
    await initialize();
    await _tts.stop();
    // Arabic locale is explicitly selected so Arabic answers are not read
    // using the device's default English voice.
    final dynamic available = await _tts.getLanguages;
    final arabicLanguages = available is List
        ? available.map((value) => value.toString())
            .where((value) => value.toLowerCase().startsWith('ar'))
            .toList()
        : <String>[];
    final arabicLocale = arabicLanguages.contains('ar-SA')
        ? 'ar-SA'
        : (arabicLanguages.isNotEmpty ? arabicLanguages.first : 'ar-SA');
    await _tts.setLanguage(arabicLocale);
    await _tts.awaitSpeakCompletion(waitForCompletion);
    try {
      await _tts.speak(value);
    } finally {
      // Keep ordinary chat playback non-blocking; voice turns opt into
      // completion so the in-chat orb remains in its speaking state.
      if (waitForCompletion) {
        await _tts.awaitSpeakCompletion(false);
      }
    }
  }

  Future<void> stop() async {
    await _tts.stop();
    _speaking = false;
  }

  Future<void> dispose() async {
    await stop();
  }
}
