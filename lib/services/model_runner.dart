import 'llama_service.dart';

/// Legacy compatibility facade over the shared GGUF runtime.
class ModelRunner {
  ModelRunner._();
  static final ModelRunner _instance = ModelRunner._();
  factory ModelRunner() => _instance;

  final LlamaService _runtime = LlamaService.instance;
  String? _modelPath;

  Future<bool> loadModel(String modelPath) async {
    final loaded = await _runtime.loadModel(modelPath);
    if (loaded) _modelPath = modelPath;
    return loaded;
  }

  Future<String> run(String input) => _runtime.generate(input);
  Future<bool> isLoaded() => _runtime.isLoaded();
  String getModelName() => _modelPath?.split('/').last ?? 'لا يوجد';

  Future<void> dispose() async {
    await _runtime.unload();
    _modelPath = null;
  }
}
