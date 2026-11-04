import 'model_service.dart';

/// Legacy compatibility facade routed through the serialized shared agent runtime.
class ModelRunner {
  ModelRunner._();
  static final ModelRunner _instance = ModelRunner._();
  factory ModelRunner() => _instance;

  final ModelService _runtime = ModelService();
  String? _modelPath;

  Future<bool> loadModel(String modelPath) async {
    final loaded = await _runtime.loadModelByPath(modelPath);
    if (loaded) _modelPath = modelPath;
    return loaded;
  }

  Future<String> run(String input) => _runtime.processInput(input);

  Future<bool> isLoaded() => _runtime.isModelLoaded();

  String getModelName() => _modelPath?.split('/').last ?? _runtime.getActiveModelName();

  /// The runtime is process-wide; legacy facade disposal must not unload it.
  Future<void> dispose() async {}
}
