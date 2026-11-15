import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
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
  static const String _baseModelUrl =
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-base.bin';
  static final http.Client _modelClient = http.Client();

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

    if (await model.exists()) await model.delete();
    final partial = File('${model.path}.part');

    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      IOSink? sink;
      try {
        var offset = await partial.exists() ? await partial.length() : 0;
        if (offset >= _baseModelBytes) {
          await partial.delete();
          offset = 0;
        }

        final request = http.Request('GET', Uri.parse(_baseModelUrl));
        if (offset > 0) request.headers['Range'] = 'bytes=$offset-';
        final response = await _modelClient
            .send(request)
            .timeout(const Duration(seconds: 60));

        if (offset > 0 && response.statusCode == 200) {
          // The server ignored Range; restart rather than append a full body.
          if (await partial.exists()) await partial.delete();
          offset = 0;
        } else if (response.statusCode == 206) {
          final contentRange = response.headers['content-range'] ?? '';
          if (!contentRange.startsWith('bytes $offset-')) {
            throw HttpException('Invalid model Content-Range: $contentRange');
          }
        } else if (response.statusCode != 200) {
          throw HttpException('Whisper model download returned HTTP ${response.statusCode}.');
        }

        sink = partial.openWrite(
          mode: offset > 0 ? FileMode.append : FileMode.write,
        );
        var received = offset;
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 60),
        )) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call((received / _baseModelBytes).clamp(0.0, 1.0).toDouble());
        }
        await sink.flush();
        await sink.close();
        sink = null;

        final actualBytes = await partial.length();
        if (actualBytes == _baseModelBytes &&
            await _sha256File(partial) == _baseModelSha256) {
          await partial.rename(model.path);
          onProgress?.call(1.0);
          return;
        }

        if (actualBytes >= _baseModelBytes) {
          await partial.delete();
          throw const FormatException(
            'Whisper Base model failed exact size/SHA-256 verification.',
          );
        }
        throw HttpException(
          'Whisper Base download incomplete: $actualBytes/$_baseModelBytes bytes.',
        );
      } catch (error) {
        lastError = error;
        try {
          await sink?.close();
        } catch (_) {}
        if (attempt < 3) {
          await Future<void>.delayed(Duration(seconds: attempt * 2));
        }
      }
    }

    throw StateError(
      'تعذر تنزيل نموذج Whisper Base والتحقق من سلامته بعد 3 محاولات: $lastError',
    );
  }

  Future<bool> _isVerifiedModel(File file) async {
    if (!await file.exists()) return false;
    if (await file.length() != _baseModelBytes) return false;
    return await _sha256File(file) == _baseModelSha256;
  }

  Future<String> _sha256File(File file) async {
    final output = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(output);
    await for (final chunk in file.openRead()) {
      input.add(chunk);
    }
    input.close();
    return output.events.single.toString();
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
