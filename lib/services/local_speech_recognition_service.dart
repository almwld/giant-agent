import 'dart:async';
import 'dart:io';

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
  String? _recordingPath;
  bool _nativeCapture = false;
  bool _initialized = false;
  bool _recording = false;
  bool _disposed = false;

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
      _recordingPath = await _capture.invokeMethod<String>('start');
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
    final path = _nativeCapture
        ? await _capture.invokeMethod<String>('stop')
        : await _whisper.stopRecording();
    _recordingPath = null;
    _nativeCapture = false;
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
      await _capture.invokeMethod<bool>('cancel');
      _recordingPath = null;
      _nativeCapture = false;
      return;
    }
    final path = await _whisper.stopRecording();
    _recordingPath = null;
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
