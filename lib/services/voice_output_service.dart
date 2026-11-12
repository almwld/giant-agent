import 'package:flutter_tts/flutter_tts.dart';

/// Shared text-to-speech output. Only explicitly offline Android voices are
/// eligible; network-required and unknown-network-status voices are rejected.
class VoiceOutputService {
  VoiceOutputService._();
  static final VoiceOutputService instance = VoiceOutputService._();

  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  bool _speaking = false;
  String? _selectedArabicVoice;

  bool get isSpeaking => _speaking;
  bool get hasOfflineArabicVoice => _selectedArabicVoice != null;

  Future<List<Map<String, dynamic>>> getAvailableVoices() async {
    final dynamic available = await _tts.getVoices;
    if (available is! List) return const <Map<String, dynamic>>[];
    return available.whereType<Map>().map((voice) {
      final item = Map<String, dynamic>.from(voice);
      return <String, dynamic>{
        'name': item['name']?.toString() ?? '',
        'locale': item['locale']?.toString() ?? '',
        if (item['quality'] != null) 'quality': item['quality'],
        if (item['gender'] != null) 'gender': item['gender'],
        if (item['network_required'] != null)
          'network_required': item['network_required'],
      };
    }).where((voice) => voice['name']!.toString().isNotEmpty)
      .toList(growable: false);
  }

  Future<void> initialize() async {
    if (_initialized) return;
    final voices = await getAvailableVoices();
    final offlineArabic = voices.where((voice) {
      final locale = voice['locale']?.toString().toLowerCase() ?? '';
      return locale.startsWith('ar') && voice['network_required'] == false;
    }).toList();
    if (offlineArabic.isEmpty) {
      _selectedArabicVoice = null;
      throw StateError(
        'لا يوجد صوت عربي محلي مثبت. ثبّت حزمة صوت عربية غير متصلة من إعدادات تحويل النص إلى كلام في Android.',
      );
    }
    offlineArabic.sort((a, b) {
      final aPreferred = a['locale'] == 'ar-SA' ? 0 : 1;
      final bPreferred = b['locale'] == 'ar-SA' ? 0 : 1;
      return aPreferred.compareTo(bPreferred);
    });
    final selected = offlineArabic.first;
    _selectedArabicVoice = selected['name']?.toString();
    await _tts.setVoice({
      'name': selected['name'],
      'locale': selected['locale'],
    });
    await _tts.setSpeechRate(0.48);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(false);
    _tts.setStartHandler(() => _speaking = true);
    _tts.setCompletionHandler(() => _speaking = false);
    _tts.setCancelHandler(() => _speaking = false);
    _tts.setErrorHandler((_) => _speaking = false);
    _initialized = true;
  }

  Future<void> speak(
    String text, {
    bool waitForCompletion = false,
  }) async {
    final value = text.trim();
    if (value.isEmpty) return;
    await initialize();
    await _tts.stop();
    await _tts.awaitSpeakCompletion(waitForCompletion);
    try {
      await _tts.speak(value);
    } finally {
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
    _initialized = false;
  }
}
