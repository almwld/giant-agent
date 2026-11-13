import 'dart:io';

import 'package:flutter_whisper/flutter_whisper.dart';

/// On-device speech recognition for Arabic conversational turns.
///
/// The Flutter 3.16-compatible whisper.cpp plugin records to an app-private
/// WAV file and transcribes it locally after the user finishes the utterance.
class LocalSpeechRecognitionService {
  LocalSpeechRecognitionService._();

  static final LocalSpeechRecognitionService instance =
      LocalSpeechRecognitionService._();

  final Whisper _whisper = Whisper();
  bool _initialized = false;
  bool _recording = false;
  bool _disposed = false;

  bool get isListening => _recording;
  bool get isModelReady => _initialized;

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
    await _whisper.startRecording();
    _recording = true;
  }

  /// Stops capture and transcribes the finished WAV locally.
  Future<String> stopListening() async {
    if (!_recording) return '';
    _recording = false;
    final path = await _whisper.stopRecording();
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
