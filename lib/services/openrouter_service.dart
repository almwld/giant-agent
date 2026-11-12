/// Backward-compatible facade for code using the former OpenRouter service name.
/// New code should use OpenAICompatibleProvider directly.
import 'openai_compatible_provider.dart';

class OpenRouterService {
  OpenRouterService._();
  static OpenAICompatibleProvider get instance =>
      OpenAICompatibleProvider.instance;
}
