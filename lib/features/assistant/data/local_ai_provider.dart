import '../domain/ai_provider.dart';

/// Adapter boundary for a real local runtime (GGUF/ONNX/TFLite).
/// A concrete engine must implement tokenizer + tensor contract + decoding;
/// a model file being present is not sufficient to claim inference support.
class LocalAiProvider implements AiProvider {
  LocalAiProvider(this.engine);
  final LocalInferenceEngine engine;

  @override
  String get id => 'local:${engine.engineId}';

  @override
  Stream<String> generate(AiGenerationRequest request) {
    if (!engine.isReady) {
      throw StateError('The selected local inference engine is not ready.');
    }
    return engine.generate(request);
  }
}
