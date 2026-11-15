import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter_whisper/flutter_whisper.dart';
import 'package:permission_handler/permission_handler.dart';

/// On-device speech recognition for Arabic conversational turns.
///
/// Android captures 16 kHz PCM through the native AEC/VAD bridge when present;
/// Whisper.cpp transcribes the resulting app-private WAV entirely on-device.
class LocalSpeechRecognitionService {
  LocalSpeechRecognitionService._();

  static final LocalSpeechRecognitionService instance =
      LocalSpeechRecognitionService._();

  final Whisper _whisper = Whisper();
  static const MethodChannel _capture = MethodChannel('giant_agent/voice_capture');
  static const EventChannel _activity = EventChannel('giant_agent/voice_activity');
  bool _nativeCapture = false;
  bool _initialized = false;
  bool _recording = false;
  bool _disposed = false;

  // Pinned official multilingual ggml-base.bin artifact. Do not silently
  // accept a non-empty/truncated cache: the upstream package checks size only.
  static const int _baseModelBytes = 147951465;
  static const String _baseModelSha256 =
      '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe';

  bool get isListening => _recording;
  bool get isModelReady => _initialized;

  /// Native 20 ms voice-activity boundaries and input level events.
  Stream<Map<String, dynamic>> get activityEvents =>
      _activity.receiveBroadcastStream().where((event) => event is Map)
          .map((event) => Map<String, dynamic>.from(event as Map));

  Future<Map<String, dynamic>> captureCapabilities() async {
    try {
      return Map<String, dynamic>.from(
        await _capture.invokeMapMethod<String, dynamic>('capabilities') ??
            const <String, dynamic>{},
      );
    } on MissingPluginException {
      return const <String, dynamic>{
        'vad': false,
        'aec_available': false,
        'noise_suppression_available': false,
      };
    }
  }

  Future<void> initialize({
    void Function(double fraction)? onProgress,
  }) async {
    if (_disposed) throw StateError('Speech service has been disposed.');
    if (_initialized) return;
    await _ensureVerifiedBaseModel(onProgress: onProgress);
    await _whisper.initialize(
      model: WhisperModel.base,
      options: const WhisperOptions(language: 'ar', threads: 4, vad: false),
      onProgress: onProgress == null
          ? null
          : (progress) => onProgress(progress.fraction.clamp(0.0, 1.0)),
    );
    _initialized = true;
  }


  Future<void> _ensureVerifiedBaseModel({
    void Function(double fraction)? onProgress,
  }) async {
    final support = await getApplicationSupportDirectory();
    final models = Directory('${support.path}/models');
    await models.create(recursive: true);
    final model = File('${models.path}/base.bin');
    if (await _isVerifiedModel(model)) return;

    // Bundled APK asset: copy locally because flutter_whisper requires a file path.
    final data = await rootBundle.load('assets/voice_models/ggml-base.bin');
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    if (bytes.length != _baseModelBytes ||
        sha256.convert(bytes).toString() != _baseModelSha256) {
      throw const FormatException('Bundled Whisper Base model failed size/SHA-256 verification.');
    }
    final partial = File('${model.path}.part');
    await partial.writeAsBytes(bytes, flush: true);
    if (!await _isVerifiedModel(partial)) {
      await partial.delete();
      throw const FormatException('Copied Whisper Base model failed verification.');
    }
    if (await model.exists()) await model.delete();
    await partial.rename(model.path);
    onProgress?.call(1.0);
  }
  Future<bool> _isVerifiedModel(File file) async {
    if (!await file.exists()) return false;
    if (await file.length() != _baseModelBytes) return false;
    return await _sha256File(file) == _baseModelSha256;
  }

  Future<String> _sha256File(File file) async {
    final output = _DigestAccumulator();
    final input = sha256.startChunkedConversion(output);
    await for (final chunk in file.openRead()) {
      input.add(chunk);
    }
    input.close();
    final digest = output.digest;
    if (digest == null) {
      throw StateError('SHA-256 stream completed without a digest.');
    }
    return digest.toString();
  }

  /// Transcribes an existing WAV file with the same verified native Whisper
  /// context used by live microphone capture.
  Future<TranscriptionResult> transcribeFile(
    String path, {
    int threads = 2,
    void Function(int percent)? onProgress,
  }) async {
    if (_disposed) throw StateError('Speech service has been disposed.');
    if (!_initialized) {
      throw StateError('Speech service must be initialized before transcription.');
    }
    return _whisper.transcribeFile(
      path,
      options: WhisperOptions(language: 'ar', threads: threads, vad: false),
      onProgress: onProgress,
    );
  }

  Future<void> startListening() async {
    if (_disposed) throw StateError('Speech service has been disposed.');
    if (_recording) return;
    await initialize();
    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      throw StateError('تم رفض إذن الميكروفون للتعرف الصوتي المحلي.');
    }
    try {
      await _capture.invokeMethod<String>('start');
      _nativeCapture = true;
    } on MissingPluginException {
      // Preserve the plugin recorder on platforms without the Android bridge.
      await _whisper.startRecording();
      _nativeCapture = false;
    }
    _recording = true;
  }

  /// Stops capture and transcribes the finished WAV locally.
  Future<String> stopListening() async {
    if (!_recording) return '';
    _recording = false;
    String? path;
    final usedNativeCapture = _nativeCapture;
    try {
      path = usedNativeCapture
          ? await _capture.invokeMethod<String>('stop')
          : await _whisper.stopRecording();
    } catch (_) {
      if (usedNativeCapture) {
        try {
          await _capture.invokeMethod<bool>('cancel');
        } catch (_) {}
      }
      rethrow;
    } finally {
      _nativeCapture = false;
    }
    if (path == null || path.isEmpty) return '';
    try {
      final result = await _whisper.transcribeFile(
        path,
        options: const WhisperOptions(language: 'ar', threads: 4, vad: false),
      );
      return result.text.trim();
    } finally {
      final recording = File(path);
      if (await recording.exists()) await recording.delete();
    }
  }

  /// Stops and discards the current recording without submitting it.
  Future<void> cancelListening() async {
    if (!_recording) return;
    _recording = false;
    if (_nativeCapture) {
      try {
        await _capture.invokeMethod<bool>('cancel');
      } finally {
        _nativeCapture = false;
      }
      return;
    }
    final path = await _whisper.stopRecording();
    final recording = File(path);
    if (await recording.exists()) await recording.delete();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await cancelListening();
    _disposed = true;
    await _whisper.dispose();
    _initialized = false;
  }
}


class _DigestAccumulator implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest value) {
    digest = value;
  }

  @override
  void close() {}
}
