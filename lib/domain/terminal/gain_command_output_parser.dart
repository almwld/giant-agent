/// Incremental parser for Gain's execution-correlated PTY completion marker.
/// It detects markers split across arbitrary stream chunks and caps captured
/// output without losing the ability to recognize a marker after the cap.
class GainCommandOutputParser {
  GainCommandOutputParser({
    required String marker,
    this.maxOutputCharacters = 1024 * 1024,
  })  : _marker = marker,
        _matcher = RegExp('${RegExp.escape(marker)}(-?\\\\d+)__') {
    if (marker.isEmpty) throw ArgumentError.value(marker, 'marker');
    if (maxOutputCharacters < 0) {
      throw ArgumentError.value(maxOutputCharacters, 'maxOutputCharacters');
    }
  }

  final String _marker;
  final RegExp _matcher;
  final int maxOutputCharacters;
  StringBuffer _output = StringBuffer();
  String _scanTail = '';
  int _receivedCharacters = 0;
  int _capturedCharacters = 0;
  int? _exitCode;

  int? get exitCode => _exitCode;
  String get output => _output.toString();
  bool get isComplete => _exitCode != null;

  void add(String chunk) {
    if (chunk.isEmpty || isComplete) return;

    final scanStart = _receivedCharacters - _scanTail.length;
    final scan = _scanTail + chunk;
    final match = _matcher.firstMatch(scan);
    final markerOffset = match == null ? null : scanStart + match.start;

    if (markerOffset != null) {
      _appendCaptured(chunk, markerOffset - _receivedCharacters);
      if (markerOffset < _capturedCharacters) {
        final current = _output.toString();
        _output = StringBuffer(current.substring(0, markerOffset));
        _capturedCharacters = markerOffset;
      }
      _exitCode = int.tryParse(match.group(1) ?? '') ?? 126;
      _receivedCharacters += chunk.length;
      return;
    }

    _appendCaptured(chunk, chunk.length);
    _receivedCharacters += chunk.length;
    final keep = _marker.length + 24;
    _scanTail = scan.length <= keep ? scan : scan.substring(scan.length - keep);
  }

  void _appendCaptured(String chunk, int requestedLength) {
    final available = maxOutputCharacters - _capturedCharacters;
    final count = requestedLength.clamp(0, available).toInt();
    if (count == 0) return;
    _output.write(chunk.substring(0, count));
    _capturedCharacters += count;
  }
}
