import 'dart:async';

/// One process-wide, typed-by-contract event channel for the chat UI.
/// Producers publish factual lifecycle/tool/native events; consumers never
/// infer stages or success from assistant prose.
class AgentEventBus {
  AgentEventBus._();

  static final AgentEventBus instance = AgentEventBus._();
  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();
  int _fallbackSequence = 0;
  final Map<String, String> _requestSessions = <String, String>{};

  Stream<Map<String, dynamic>> get events => _controller.stream;

  void bindRequest(String requestId, String sessionId) {
    if (requestId.isNotEmpty && sessionId.isNotEmpty) {
      _requestSessions[requestId] = sessionId;
    }
  }

  void unbindRequest(String requestId) => _requestSessions.remove(requestId);

  void publish(Map<dynamic, dynamic> source) {
    final event = _jsonSafeMap(source);
    final now = DateTime.now().toUtc().toIso8601String();
    final id = event['id']?.toString() ?? '';
    if (id.isEmpty) {
      event['id'] = 'bus_${DateTime.now().microsecondsSinceEpoch}_${++_fallbackSequence}';
    }
    final requestId = event['request_id']?.toString() ?? '';
    final sessionId = _requestSessions[requestId];
    if (sessionId != null) event.putIfAbsent('session_id', () => sessionId);
    event.putIfAbsent('timestamp', () => now);
    event.putIfAbsent('type', () => 'unknown');
    event.putIfAbsent('status', () => 'pending');
    _controller.add(Map<String, dynamic>.unmodifiable(event));
  }

  Map<String, dynamic> _jsonSafeMap(Map<dynamic, dynamic> source) {
    final result = <String, dynamic>{};
    source.forEach((key, value) {
      if (key is String) result[key] = _jsonSafeValue(value);
    });
    return result;
  }

  dynamic _jsonSafeValue(dynamic value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Map) return _jsonSafeMap(value);
    if (value is Iterable) return value.map(_jsonSafeValue).toList(growable: false);
    return value.toString();
  }
}
