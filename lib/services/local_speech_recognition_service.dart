import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

/// On-device speech recognition for conversational voice turns.
///
/// Models are stored in the app's private support directory. No speech audio
/// or transcript is sent to a remote endpoint by this service.
class LocalSpeechRecognitionService {
  LocalSpeechRecognitionService._();

  static final LocalSpeechRecognitionService instance =
      LocalSpeechRecognitionService._();

  static const String modelFileName = 'ggml-base.bin';
  static const String modelUrl =
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin';

  final WhisperModelManager _models = WhisperModelManager();
  WhisperEngine? _engine;
  dynamic _activeTask;
  StreamSubscription<dynamic>? _updates;
  bool _loading = false;
  bool _disposed = false;

  bool get isListening => _activeTask != null;
  bool get isModelReady => _engine != null;

  Future<File?> installedModel() async {
    final model = await _models.find(modelFileName);
    if (model == null) return null;
    final file = File(model.path);
    return await file.exists() ? file : null;
  }

  /// Downloads the multilingual base model once. The caller can expose
  /// [onProgress] in the UI; synthesis and inference remain offline afterward.
  Future<void> downloadModel({
    void Function(double fraction)? onProgress,
  }) async {
    if (_loading) throw StateError('A speech model operation is already active.');
    _loading = true;
    try {
      await for (final progress in _models.download(
        Uri.parse(modelUrl),
        modelFileName,
      )) {
        onProgress?.call(progress.fraction.clamp(0.0, 1.0));
      }
      final file = await installedModel();
      if (file == null) {
        throw StateError('Whisper model download did not produce a valid file.');
      }
    } finally {
      _loading = false;
    }
  }

  Future<bool> initialize() async {
    if (_disposed) throw StateError('Speech service has been disposed.');
    if (_engine != null) return true;
    if (_loading) throw StateError('Speech model is being prepared.');
    final file = await installedModel();
    if (file == null) return false;
    _loading = true;
    try {
      _engine = await WhisperEngine.load(
        file.path,
        config: const WhisperConfig(backend: WhisperBackend.automatic),
      );
      return true;
    } finally {
      _loading = false;
    }
  }

  /// Starts local microphone transcription. Updates are provisional until
  /// [stopListening] flushes the final audio window.
  Future<void> startListening({
    required void Function(String text) onText,
    void Function(Object error)? onError,
  }) async {
    if (_disposed) throw StateError('Speech service has been disposed.');
    if (_activeTask != null) return;
    final ready = await initialize();
    if (!ready) {
      throw StateError('LOCAL_WHISPER_MODEL_MISSING');
    }
    final engine = _engine!;
    final task = await engine.transcribeMicrophone(
      options: const TranscribeOptions(
        language: 'ar',
        tokenTimestamps: false,
      ),
    );
    _activeTask = task;
    _updates = task.updates.listen(
      (update) {
        if (_disposed || !identical(_activeTask, task)) return;
        final text = update.text.trim();
        if (text.isNotEmpty) onText(text);
      },
      onError: (Object error, StackTrace stack) {
        onError?.call(error);
      },
    );
  }

  Future<String> stopListening() async {
    final task = _activeTask;
    if (task == null) return '';
    _activeTask = null;
    await _updates?.cancel();
    _updates = null;
    final result = await task.stop();
    return result.confirmedText.trim();
  }

  Future<void> cancelListening() async {
    final task = _activeTask;
    _activeTask = null;
    await _updates?.cancel();
    _updates = null;
    if (task != null) {
      try {
        await task.cancel();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await cancelListening();
    _engine?.dispose();
    _engine = null;
    await _models.close();
  }
}
