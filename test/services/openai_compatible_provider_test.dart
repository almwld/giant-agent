import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/services/openai_compatible_provider.dart';

void main() {
  group('OpenAICompatibleProvider.chatCompletionsUri', () {
    test('builds the official OpenRouter chat completions endpoint', () {
      expect(
        OpenAICompatibleProvider.chatCompletionsUri(OpenAICompatibleProvider.defaultBaseUrl),
        Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
      );
    });

    test('rejects arbitrary OpenAI-compatible providers', () {
      expect(
        () => OpenAICompatibleProvider.chatCompletionsUri('https://api.example.com/v1'),
        throwsArgumentError,
      );
    });

    test('rejects Gemini native endpoint from the OpenRouter adapter', () {
      expect(
        () => OpenAICompatibleProvider.chatCompletionsUri(
          'https://generativelanguage.googleapis.com/v1beta/openai',
        ),
        throwsArgumentError,
      );
    });

    test('extracts plain text response content', () {
      expect(
        OpenAICompatibleProvider.extractText({
          'choices': [{'message': {'content': 'Hello'}}]
        }),
        'Hello',
      );
    });

    test('extracts multimodal text parts', () {
      expect(
        OpenAICompatibleProvider.extractText({
          'choices': [{'message': {'content': [
            {'type': 'text', 'text': 'first'},
            {'type': 'text', 'text': 'second'},
          ]}}]
        }),
        'first\nsecond',
      );
    });
  });
}
