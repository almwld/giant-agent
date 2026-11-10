import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/services/gemini_provider.dart';
import 'package:giant_agent_x/services/openai_compatible_provider.dart';

void main() {
  group('Gemini native API contract', () {
    test('builds the native generateContent endpoint', () {
      expect(
        GeminiProvider.generateContentUri('gemini-flash-latest'),
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent'),
      );
    });

    test('rejects path injection in model ids', () {
      expect(() => GeminiProvider.generateContentUri('../other'), throwsArgumentError);
    });

    test('extracts text from candidate content parts', () {
      expect(
        GeminiProvider.extractText({
          'candidates': [{
            'content': {'parts': [{'text': 'Hello'}, {'text': 'world'}]}
          }]
        }),
        'Hello\nworld',
      );
    });

    test('reports a blocked response when no candidate exists', () {
      expect(
        () => GeminiProvider.extractText({
          'promptFeedback': {'blockReason': 'SAFETY'}
        }),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('SAFETY'))),
      );
    });
  });

  group('OpenRouter endpoint policy', () {
    test('uses only the official OpenRouter endpoint', () {
      expect(
        OpenAICompatibleProvider.chatCompletionsUri(OpenAICompatibleProvider.defaultBaseUrl),
        Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
      );
    });

    test('rejects arbitrary OpenAI-compatible endpoints', () {
      expect(
        () => OpenAICompatibleProvider.chatCompletionsUri('https://api.example.com/v1'),
        throwsArgumentError,
      );
    });

    test('extracts OpenRouter message content', () {
      expect(
        OpenAICompatibleProvider.extractText({
          'choices': [{'message': {'content': 'response'}}]
        }),
        'response',
      );
    });
  });
}
