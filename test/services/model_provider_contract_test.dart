import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/services/openai_compatible_provider.dart';

void main() {
  group('OpenRouter endpoint policy', () {
    test('uses only the official OpenRouter endpoint', () {
      expect(
        OpenAICompatibleProvider.chatCompletionsUri(
          OpenAICompatibleProvider.defaultBaseUrl,
        ),
        Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
      );
    });

    test('rejects arbitrary OpenAI-compatible endpoints', () {
      expect(
        () => OpenAICompatibleProvider.chatCompletionsUri(
          'https://api.example.com/v1',
        ),
        throwsArgumentError,
      );
    });

    test('recognizes only the official HTTPS OpenRouter base URL', () {
      expect(
        OpenAICompatibleProvider.isOfficialBaseUrl(
          'https://openrouter.ai/api/v1',
        ),
        isTrue,
      );
      expect(
        OpenAICompatibleProvider.isOfficialBaseUrl(
          'https://api.example.com/v1',
        ),
        isFalse,
      );
      expect(
        OpenAICompatibleProvider.isOfficialBaseUrl(
          'http://openrouter.ai/api/v1',
        ),
        isFalse,
      );
    });

    test('decodes Arabic JSON from UTF-8 response bytes', () {
      final bytes = utf8.encode(jsonEncode({'text': 'مرحباً بالعالم'}));
      expect(
        OpenAICompatibleProvider.decodeJsonResponse(bytes)['text'],
        'مرحباً بالعالم',
      );
    });

    test('extracts OpenRouter message content', () {
      expect(
        OpenAICompatibleProvider.extractText({
          'choices': [
            {'message': {'content': 'response'}}
          ]
        }),
        'response',
      );
    });
  });
}
