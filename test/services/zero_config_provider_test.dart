import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/services/providers/zero_config_provider.dart';

void main() {
  group('ZeroConfigProvider.extractText', () {
    test('extracts OpenAI-compatible assistant content', () {
      final result = ZeroConfigProvider.extractText({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': 'مرحباً بك'},
          }
        ],
      });
      expect(result, 'مرحباً بك');
    });

    test('extracts text from a plain-text legacy response', () {
      expect(ZeroConfigProvider.extractText('  أهلاً  '), 'أهلاً');
    });

    test('rejects an empty or unsupported response', () {
      expect(
        () => ZeroConfigProvider.extractText({'choices': []}),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
