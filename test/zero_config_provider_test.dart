import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/services/providers/zero_config_provider.dart';

void main() {
  group('ZeroConfigProvider.extractText', () {
    test('extracts OpenAI-compatible message content', () {
      expect(
        ZeroConfigProvider.extractText({
          'choices': [
            {'message': {'content': 'مرحباً'}}
          ]
        }),
        'مرحباً',
      );
    });

    test('extracts multipart message content', () {
      expect(
        ZeroConfigProvider.extractText({
          'choices': [
            {'message': {'content': [
              {'type': 'text', 'text': 'hello'},
              {'type': 'text', 'text': 'world'}
            ]}}
          ]
        }),
        'hello\nworld',
      );
    });

    test('accepts legacy plain text responses', () {
      expect(ZeroConfigProvider.extractText('  ready  '), 'ready');
    });

    test('rejects empty or unsupported payloads', () {
      expect(
        () => ZeroConfigProvider.extractText({'choices': []}),
        throwsFormatException,
      );
    });
  });
}
