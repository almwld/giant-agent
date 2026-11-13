import '../domain/kernel/agent_kernel_store.dart';

/// Analytics projection over the canonical durable execution journal.
///
/// This service deliberately does not open a second SQLite database. The old
/// analytics.db file is left untouched on disk for compatibility/recovery;
/// new aggregate facts are appended to agent_events with a null request owner.
class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();

  final AgentKernelStore _store = AgentKernelStore();
  Future<void>? _initialization;
  int _sessionSequence = 0;

  Future<void> init() {
    final active = _initialization;
    if (active != null) return active;
    late final Future<void> shared;
    shared = _store.database.then((_) {}).whenComplete(() {
      if (identical(_initialization, shared)) _initialization = null;
    });
    _initialization = shared;
    return shared;
  }

  /// Records only bounded, non-content metadata. Prompt text, model output,
  /// tool arguments, credentials and arbitrary nested payloads are excluded.
  Future<void> trackEvent(String eventType, {Map<String, dynamic>? data}) async {
    await init();
    final safe = <String, Object?>{};
    const allowedKeys = <String>{
      'provider', 'model', 'mode', 'status', 'duration_ms',
      'tool_name', 'tool_call_id', 'success', 'count', 'category',
    };
    for (final entry in (data ?? const <String, dynamic>{}).entries) {
      if (!allowedKeys.contains(entry.key)) continue;
      final value = entry.value;
      if (value == null || value is bool || value is num) {
        safe[entry.key] = value;
      } else if (value is String && value.length <= 120) {
        safe[entry.key] = value;
      }
    }
    await _store.appendAnalyticsEvent(eventType: eventType, data: safe);
  }

  Future<void> startSession() async {
    await trackEvent('session_started', data: <String, dynamic>{
      'count': ++_sessionSequence,
    });
  }

  Future<void> endSession(int sessionId, int messageCount) async {
    await trackEvent('session_ended', data: <String, dynamic>{
      'count': messageCount < 0 ? 0 : messageCount,
    });
  }

  /// Reads counts from the same SQLite journal used by AgentService/Timeline.
  Future<Map<String, dynamic>> getStats() async {
    await init();
    final db = await _store.database;
    final eventCount = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM agent_events',
    );
    final requestCount = await db.rawQuery(
      'SELECT COUNT(DISTINCT conversation_id) AS count FROM agent_requests',
    );
    final analyticsCount = await db.rawQuery(
      "SELECT COUNT(*) AS count FROM agent_events WHERE type LIKE 'analytics_%'",
    );
    return <String, dynamic>{
      'total_events': (eventCount.first['count'] as num?)?.toInt() ?? 0,
      'total_sessions': (requestCount.first['count'] as num?)?.toInt() ?? 0,
      'analytics_events': (analyticsCount.first['count'] as num?)?.toInt() ?? 0,
      'last_updated': DateTime.now(),
    };
  }

  /// The store is process-scoped and shared with AgentService; do not close it
  /// from a screen or a short-lived analytics consumer.
  void dispose() {}
}
