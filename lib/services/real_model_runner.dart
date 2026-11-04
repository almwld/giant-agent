import 'llama_service.dart';

/// Compatibility facade for older callers. The app owns one GGUF/JNI runtime.
class RealModelRunner {
  RealModelRunner._();
  static final RealModelRunner _instance = RealModelRunner._();
  factory RealModelRunner() => _instance;

  final LlamaService _runtime = LlamaService.instance;
  String? _modelPath;
  bool _isLoading = false;

  Future<bool> loadModel(String modelPath) async {
    if (_isLoading) return false;
    _isLoading = true;
    try {
      final loaded = await _runtime.loadModel(modelPath);
      if (loaded) _modelPath = modelPath;
      return loaded;
    } finally {
      _isLoading = false;
    }
  }

  Future<String> run(String input) => _runtime.generate(input);
  Future<bool> isLoaded() => _runtime.isLoaded();
  bool isLoading() => _isLoading;
  String getModelName() => _modelPath?.split('/').last ?? 'لا يوجد';

  Future<void> dispose() async {
    await _runtime.unload();
    _modelPath = null;
  }
}
