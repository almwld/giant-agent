import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/services/local_voice_text_chunker.dart';

void main() {
  group('LocalVoiceTextChunker', () {
    test('returns no chunks for blank input', () {
      expect(LocalVoiceTextChunker.split('  \n  '), isEmpty);
    });

    test('keeps every chunk within the configured character limit', () {
      final text = List<String>.filled(90, 'مرحبا').join(' ');
      final chunks = LocalVoiceTextChunker.split(text, maxCharacters: 48);
      expect(chunks, isNotEmpty);
      expect(chunks.every((chunk) => chunk.length <= 48), isTrue);
      expect(chunks.join(' '), text);
    });

    test('splits unusually long tokens without dropping characters', () {
      final token = 'ع' * 401;
      final chunks = LocalVoiceTextChunker.split(token, maxCharacters: 100);
      expect(chunks.map((chunk) => chunk.length), [100, 100, 100, 100, 1]);
      expect(chunks.join(), token);
    });

    test('rejects a non-positive chunk limit', () {
      expect(
        () => LocalVoiceTextChunker.split('مرحبا', maxCharacters: 0),
        throwsArgumentError,
      );
    });
  });
}
