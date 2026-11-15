import 'package:flutter_tts/flutter_tts.dart';

import 'local_arabic_tts_service.dart';

/// Shared text-to-speech output. Only explicitly offline Android voices are
/// eligible; network-required and unknown-network-status voices are rejected.
class VoiceOutputService {
  VoiceOutputService._();
  static final VoiceOutputService instance = VoiceOutputService._();

  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  bool _speaking = false;
  String? _selectedArabicVoice;
  String _streamBuffer = '';
  Future<void> _streamQueue = Future<void>.value();
  bool _streaming = false;
  int _streamedCharacters = 0;
  bool _useNabra = false;
  int _speechEpoch = 0;
  bool _interrupted = false;

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
    final localTts = LocalArabicTtsService.instance;
    if (await localTts.isInstalled()) {
      await localTts.initialize();
      _useNabra = true;
      _initialized = true;
      return;
    }
    _useNabra = false;
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

  Future<void> refresh() async {
    _initialized = false;
    await initialize();
  }

  Future<void> beginStreaming() async {
    await initialize();
    _speechEpoch++;
    _interrupted = false;
    _streamBuffer = '';
    _streamedCharacters = 0;
    _streamQueue = Future<void>.value();
    _streaming = true;
  }

  /// Adds safe user-visible answer text to the local speech queue. Complete
  /// sentence-sized chunks are spoken while the model is still generating.
  void addStreamingText(String delta) {
    if (!_streaming || delta.isEmpty) return;
    _streamBuffer += delta;
    final boundary = RegExp(r'[.!?؟؛،\n。！？]');
    var cut = -1;
    for (var i = 0; i < _streamBuffer.length; i++) {
      if (boundary.hasMatch(_streamBuffer[i]) &&
          _streamBuffer.substring(0, i + 1).trim().length >= 18) {
        cut = i + 1;
      }
    }
    if (cut < 0) return;
    final chunk = _streamBuffer.substring(0, cut).trim();
    _streamBuffer = _streamBuffer.substring(cut).trimLeft();
    if (chunk.isEmpty) return;
    _streamedCharacters += chunk.length;
    final epoch = _speechEpoch;
    _streamQueue = _streamQueue.then((_) => _speakSegment(chunk, epoch: epoch));
  }

  Future<void> finishStreaming(String fallbackText) async {
    if (!_streaming) {
      if (_interrupted) return;
      await speak(fallbackText, waitForCompletion: true);
      return;
    }
    _streaming = false;
    final tail = _streamBuffer.trim();
    _streamBuffer = '';
    if (tail.isNotEmpty) {
      _streamedCharacters += tail.length;
      final epoch = _speechEpoch;
      _streamQueue = _streamQueue.then((_) => _speakSegment(tail, epoch: epoch));
    }
    if (_streamedCharacters == 0 && fallbackText.trim().isNotEmpty) {
      final epoch = _speechEpoch;
      _streamQueue = _streamQueue.then((_) => _speakSegment(fallbackText.trim(), epoch: epoch));
    }
    await _streamQueue;
    await _tts.awaitSpeakCompletion(false);
  }

  Future<void> _speakSegment(
    String text, {
    required int epoch,
  }) async {
    if (text.trim().isEmpty || epoch != _speechEpoch) return;
    _speaking = true;
    try {
      if (_useNabra) {
        await LocalArabicTtsService.instance.speak(text.trim());
      } else {
        await _tts.awaitSpeakCompletion(true);
        if (epoch != _speechEpoch) return;
        await _tts.speak(text.trim());
      }
    } finally {
      _speaking = false;
    }
  }

  Future<void> speak(
    String text, {
    bool waitForCompletion = false,
  }) async {
    final value = text.trim();
    if (value.isEmpty) return;
    await initialize();
    _speechEpoch++;
    _interrupted = false;
    final epoch = _speechEpoch;
    _streaming = false;
    _streamBuffer = '';
    if (_useNabra) {
      _speaking = true;
      try {
        await LocalArabicTtsService.instance.stop();
        if (epoch != _speechEpoch) return;
        await LocalArabicTtsService.instance.speak(value);
      } finally {
        _speaking = false;
      }
      return;
    }
    await _tts.stop();
    await _tts.awaitSpeakCompletion(waitForCompletion);
    try {
      await _tts.speak(value);
    } finally {
      if (waitForCompletion) await _tts.awaitSpeakCompletion(false);
    }
  }

  Future<void> stop() async {
    _speechEpoch++;
    _interrupted = true;
    _streaming = false;
    _streamBuffer = '';
    await _tts.stop();
    await LocalArabicTtsService.instance.stop();
    _speaking = false;
  }

  Future<void> dispose() async {
    await stop();
    _initialized = false;
  }
}
