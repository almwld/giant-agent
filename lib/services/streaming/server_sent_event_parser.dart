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
  final List<String> _data = <String>[];
  String _event = '';
  String? _id;
  Duration? _retry;
  bool _sawCarriageReturn = false;
  String _lastEventId = '';

  String get lastEventId => _lastEventId;

  List<ServerSentEvent> add(List<int> bytes) {
    final text = utf8.decode(bytes, allowMalformed: false);
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
      case 'event':
        _event = value;
      case 'id':
        if (!value.contains('\u0000')) _id = value;
      case 'retry':
        final milliseconds = int.tryParse(value);
        if (milliseconds != null && milliseconds >= 0) {
          _retry = Duration(milliseconds: milliseconds);
        }
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
      data: _data.join('\\n'),
      id: id,
      retry: _retry,
    ));
    _data.clear();
    _event = '';
    _id = null;
    _retry = null;
  }
}
