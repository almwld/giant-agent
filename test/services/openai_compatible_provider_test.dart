import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/services/openai_compatible_provider.dart';

void main() {
  group('OpenAICompatibleProvider.chatCompletionsUri', () {
    test('appends chat completions to a versioned base URL', () {
      expect(
        OpenAICompatibleProvider.chatCompletionsUri('https://api.example.com/v1'),
        Uri.parse('https://api.example.com/v1/chat/completions'),
      );
    });

    test('does not duplicate an existing chat completions path', () {
      expect(
        OpenAICompatibleProvider.chatCompletionsUri(
          'https://api.example.com/v1/chat/completions/',
        ),
        Uri.parse('https://api.example.com/v1/chat/completions'),
      );
    });

    test('supports providers with a custom API prefix', () {
      expect(
        OpenAICompatibleProvider.chatCompletionsUri(
          'https://generativelanguage.googleapis.com/v1beta/openai',
        ),
        Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
        ),
      );
    });
  });
}
