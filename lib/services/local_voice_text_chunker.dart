/// Splits long Arabic text into bounded utterances for local neural TTS.
///
/// Nabra's Kokoro frontend has a fixed phoneme sequence limit. Keeping chunks
/// short avoids native process failures and bounds latency between interrupts.
class LocalVoiceTextChunker {
  const LocalVoiceTextChunker._();

  static List<String> split(String text, {int maxCharacters = 100}) {
    if (maxCharacters < 1) {
      throw ArgumentError.value(maxCharacters, 'maxCharacters');
    }
    final remaining = text.trim();
    if (remaining.isEmpty) return const [];
    final words = remaining.split(RegExp(r'\s+'));
    final chunks = <String>[];
    var current = '';
    for (final word in words) {
      if (word.length > maxCharacters) {
        if (current.isNotEmpty) {
          chunks.add(current);
          current = '';
        }
        for (var offset = 0; offset < word.length; offset += maxCharacters) {
          chunks.add(word.substring(
            offset,
            (offset + maxCharacters).clamp(0, word.length),
          ));
        }
        continue;
      }
      final candidate = current.isEmpty ? word : '$current $word';
      if (candidate.length > maxCharacters && current.isNotEmpty) {
        chunks.add(current);
        current = word;
      } else {
        current = candidate;
      }
    }
    if (current.isNotEmpty) chunks.add(current);
    return chunks;
  }
}
