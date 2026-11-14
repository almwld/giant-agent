import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

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
  Future<void>? _bundledModelInstall;

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

  Future<void> _ensureBundledModel() {
    final pending = _bundledModelInstall;
    if (pending != null) return pending;
    final install = _copyBundledWhisperModel();
    _bundledModelInstall = install;
    return install.whenComplete(() {
      if (identical(_bundledModelInstall, install)) _bundledModelInstall = null;
    });
  }

  Future<void> _copyBundledWhisperModel() async {
    final support = await getApplicationSupportDirectory();
    final models = Directory('${support.path}/models');
    await models.create(recursive: true);
    final destination = File('${models.path}/base.bin');
    const expectedBytes = 147951465;
    const expectedSha256 = '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe';
    if (await destination.exists() && await destination.length() == expectedBytes) {
      final digest = await sha256.bind(destination.openRead()).first;
      if (digest.toString() == expectedSha256) return;
    }
    final asset = await rootBundle.load('assets/voice_models/ggml-base.bin');
    final bytes = asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes);
    if (bytes.length != expectedBytes || sha256.convert(bytes).toString() != expectedSha256) {
      throw const FormatException('Bundled Whisper Base model failed SHA-256/size validation.');
    }
    final temporary = File('${destination.path}.bundled.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    if (await destination.exists()) await destination.delete();
    await temporary.rename(destination.path);
  }

  Future<void> initialize({
    void Function(double fraction)? onProgress,
  }) async {
    if (_disposed) throw StateError('Speech service has been disposed.');
    if (_initialized) return;
    await _ensureBundledModel();
    await _whisper.initialize(
      model: WhisperModel.base,
      onProgress: onProgress == null
          ? null
          : (progress) => onProgress(progress.fraction.clamp(0.0, 1.0)),
    );
    _initialized = true;
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
      final result = await _whisper.transcribeFile(path);
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
