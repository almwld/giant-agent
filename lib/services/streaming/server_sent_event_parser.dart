import 'dart:convert';

/// Incremental Server-Sent Events parser supporting CRLF, LF, multi-line data,
/// comments, event IDs, retry hints and UTF-8 chunk boundaries.
class ServerSentEvent {
  const ServerSentEvent({this.event = 'message', this.data = '', this.id, this.retry});
  final String event;
  final String data;
  final String? id;
  final Duration? retry;
}

class ServerSentEventParser {
  final StringBuffer _line = StringBuffer();
  List<int> _pendingUtf8 = <int>[];
  final List<String> _data = <String>[];
  String _event = '';
  String? _id;
  Duration? _retry;
  bool _sawCarriageReturn = false;
  String _lastEventId = '';

  String get lastEventId => _lastEventId;


  String _decodeChunk(List<int> bytes) {
    final combined = <int>[..._pendingUtf8, ...bytes];
    _pendingUtf8 = <int>[];
    for (var tail = 0; tail <= 3 && tail <= combined.length; tail++) {
      final split = combined.length - tail;
      try {
        final decoded = utf8.decode(combined.sublist(0, split), allowMalformed: false);
        if (tail > 0) _pendingUtf8 = combined.sublist(split);
        return decoded;
      } on FormatException {
        if (tail == 3) rethrow;
      }
    }
    throw const FormatException('Invalid UTF-8 in SSE stream.');
  }

  List<ServerSentEvent> add(List<int> bytes) {
    final text = _decodeChunk(bytes);
    final events = <ServerSentEvent>[];
    for (final unit in text.codeUnits) {
      if (_sawCarriageReturn) {
        _sawCarriageReturn = false;
        if (unit == 10) continue;
      }
      if (unit == 13) {
        _consumeLine(events);
        _sawCarriageReturn = true;
      } else if (unit == 10) {
        _consumeLine(events);
      } else {
        _line.writeCharCode(unit);
      }
    }
    return events;
  }

  List<ServerSentEvent> close() {
    if (_pendingUtf8.isNotEmpty) {
      _line.write(utf8.decode(_pendingUtf8, allowMalformed: false));
      _pendingUtf8 = <int>[];
    }
    final events = <ServerSentEvent>[];
    if (_line.length > 0) _consumeLine(events);
    _dispatch(events);
    return events;
  }

  void _consumeLine(List<ServerSentEvent> events) {
    final line = _line.toString();
    _line.clear();
    if (line.isEmpty) {
      _dispatch(events);
      return;
    }
    if (line.startsWith(':')) return;
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'data':
        _data.add(value);
        break;
      case 'event':
        _event = value;
        break;
      case 'id':
        if (!value.contains('\u0000')) _id = value;
        break;
      case 'retry':
        final milliseconds = int.tryParse(value);
        if (milliseconds != null && milliseconds >= 0) {
          _retry = Duration(milliseconds: milliseconds);
        }
        break;
      default:
        break;
    }
  }

  void _dispatch(List<ServerSentEvent> events) {
    if (_data.isEmpty) {
      _event = '';
      _id = null;
      return;
    }
    final id = _id ?? _lastEventId;
    if (_id != null) _lastEventId = _id!;
    events.add(ServerSentEvent(
      event: _event.isEmpty ? 'message' : _event,
      data: _data.join('\n'),
      id: id,
      retry: _retry,
    ));
    _data.clear();
    _event = '';
    _id = null;
    _retry = null;
  }
}
