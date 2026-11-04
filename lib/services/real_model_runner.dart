import 'model_service.dart';

/// Compatibility facade for older callers. It never owns or unloads the
/// process-wide GGUF/JNI runtime.
class RealModelRunner {
  RealModelRunner._();
  static final RealModelRunner _instance = RealModelRunner._();
  factory RealModelRunner() => _instance;

  final ModelService _runtime = ModelService();
  String? _modelPath;

  Future<bool> loadModel(String modelPath) async {
    final loaded = await _runtime.loadModelByPath(modelPath);
    if (loaded) _modelPath = modelPath;
    return loaded;
  }

  Future<String> run(String input) => _runtime.processInput(input);

  Future<bool> isLoaded() => _runtime.isModelLoaded();

  bool isLoading() => _runtime.isBusy;

  String getModelName() => _modelPath?.split('/').last ?? _runtime.getActiveModelName();

  /// The runtime is process-wide; legacy facade disposal must not unload it.
  Future<void> dispose() async {}
}
