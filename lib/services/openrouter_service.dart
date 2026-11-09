/// Backward-compatible import for code that used the former OpenRouter service name.
/// New code should import openai_compatible_provider.dart directly.
export 'openai_compatible_provider.dart' show OpenAICompatibleProvider;
typedef OpenRouterService = OpenAICompatibleProvider;
