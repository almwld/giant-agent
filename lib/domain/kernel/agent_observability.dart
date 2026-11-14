import 'dart:convert';

import 'agent_kernel_store.dart';

/// A locally persisted execution event with a stable SQLite cursor.
class AgentObservabilityEvent {
  const AgentObservabilityEvent({
    required this.rowId,
    required this.id,
    required this.requestId,
    required this.taskId,
    required this.type,
    required this.status,
    required this.payload,
    required this.createdAt,
  });

  final int rowId;
  final String id;
  final String requestId;
  final String? taskId;
  final String type;
  final String status;
  final Map<String, Object?> payload;
  final DateTime createdAt;
}

/// A cursor-based page. [nextCursor] is null when there are no older rows.
class AgentObservabilityPage {
  const AgentObservabilityPage({
    required this.events,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<AgentObservabilityEvent> events;
  final int? nextCursor;
  final bool hasMore;
}

/// Aggregates factual local execution metrics without exposing prompt content.
class AgentObservabilitySummary {
  const AgentObservabilitySummary({
    required this.requestCount,
    required this.activeRequests,
    required this.completedRequests,
    required this.failedRequests,
    required this.interruptedRequests,
    required this.eventCount,
    required this.toolCallCount,
    required this.toolFailureCount,
    required this.averageToolLatencyMs,
    required this.eventTypes,
  });

  final int requestCount;
  final int activeRequests;
  final int completedRequests;
  final int failedRequests;
  final int interruptedRequests;
  final int eventCount;
  final int toolCallCount;
  final int toolFailureCount;
  final double? averageToolLatencyMs;
  final Map<String, int> eventTypes;

  double get toolSuccessRate => toolCallCount == 0
      ? 1
      : (toolCallCount - toolFailureCount).clamp(0, toolCallCount).toDouble() /
          toolCallCount;
}

/// Read-only observability queries over the existing durable kernel database.
extension AgentKernelObservability on AgentKernelStore {
  /// Reads the newest events first. Pass [beforeRowId] from the previous page
  /// to continue without offset-based pagination drift while new events arrive.
  Future<AgentObservabilityPage> observabilityEventsForConversation(
    String conversationId, {
    int? beforeRowId,
    int limit = 50,
    String? type,
    String? status,
    String? search,
  }) async {
    final boundedLimit = limit.clamp(1, 200).toInt();
    final where = <String>['r.conversation_id = ?'];
    final args = <Object?>[conversationId];
    if (beforeRowId != null) {
      where.add('e.row_id < ?');
      args.add(beforeRowId);
    }
    if (type != null && type.isNotEmpty) {
      where.add('e.type = ?');
      args.add(type);
    }
    if (status != null && status.isNotEmpty) {
      where.add('e.status = ?');
      args.add(status);
    }
    final normalizedSearch = search?.trim().toLowerCase();
    if (normalizedSearch != null && normalizedSearch.isNotEmpty) {
      where.add(\"lower(e.type || ' ' || e.status || ' ' || e.id || ' ' || COALESCE(e.task_id, '') || ' ' || e.payload_json) LIKE ?\");
      args.add('%$normalizedSearch%');
    }
    args.add(boundedLimit + 1);

    final rows = await (await database).rawQuery('''
      SELECT e.row_id, e.id, e.request_id, e.task_id, e.type, e.status,
             e.payload_json, e.created_at
      FROM agent_events e
      INNER JOIN agent_requests r ON r.id = e.request_id
      WHERE ${where.join(' AND ')}
      ORDER BY e.row_id DESC
      LIMIT ?
    ''', args);

    final hasMore = rows.length > boundedLimit;
    final visibleRows = hasMore ? rows.take(boundedLimit).toList() : rows;
    final events = visibleRows.map((row) {
      final decoded = jsonDecode(row['payload_json']! as String);
      if (decoded is! Map) {
        throw const FormatException('Stored observability event is not an object.');
      }
      return AgentObservabilityEvent(
        rowId: row['row_id']! as int,
        id: row['id']! as String,
        requestId: row['request_id']! as String,
        taskId: row['task_id'] as String?,
        type: row['type']! as String,
        status: row['status']! as String,
        payload: Map<String, Object?>.from(decoded),
        createdAt: DateTime.parse(row['created_at']! as String),
      );
    }).toList(growable: false);

    return AgentObservabilityPage(
      events: events,
      nextCursor: hasMore && events.isNotEmpty ? events.last.rowId : null,
      hasMore: hasMore,
    );
  }

  /// Returns safe aggregate counters for a conversation. It deliberately
  /// excludes request prompts, model responses, tool arguments and tool output.
  Future<AgentObservabilitySummary> observabilitySummaryForConversation(
    String conversationId,
  ) async {
    final db = await database;
    final requestRows = await db.rawQuery('''
      SELECT status, COUNT(*) AS count
      FROM agent_requests
      WHERE conversation_id = ?
      GROUP BY status
    ''', [conversationId]);
    final requestCounts = <String, int>{
      for (final row in requestRows)
        row['status']! as String: (row['count']! as num).toInt(),
    };
    final eventRows = await db.rawQuery('''
      SELECT e.type, e.status, e.payload_json
      FROM agent_events e
      INNER JOIN agent_requests r ON r.id = e.request_id
      WHERE r.conversation_id = ?
      ORDER BY e.row_id ASC
    ''', [conversationId]);

    final eventTypes = <String, int>{};
    final toolCalls = <String>{};
    final failedToolCalls = <String>{};
    final latencies = <double>[];
    for (final row in eventRows) {
      final eventType = row['type']! as String;
      final eventStatus = row['status']! as String;
      eventTypes.update(eventType, (value) => value + 1, ifAbsent: () => 1);
      final decoded = jsonDecode(row['payload_json']! as String);
      if (decoded is! Map) continue;
      final payload = Map<String, Object?>.from(decoded);
      final callId = payload['tool_call_id']?.toString();
      if (callId == null || callId.isEmpty) continue;
      toolCalls.add(callId);
      if (eventStatus == 'failed' ||
          eventStatus == 'error' ||
          eventType.contains('failed')) {
        failedToolCalls.add(callId);
      }
      final latency = payload['duration_ms'] ?? payload['latency_ms'];
      if (latency is num && latency >= 0) latencies.add(latency.toDouble());
    }

    final active = (requestCounts['queued'] ?? 0) +
        (requestCounts['running'] ?? 0);
    final latencyAverage = latencies.isEmpty
        ? null
        : latencies.reduce((a, b) => a + b) / latencies.length;
    return AgentObservabilitySummary(
      requestCount: requestCounts.values.fold(0, (a, b) => a + b),
      activeRequests: active,
      completedRequests: requestCounts['completed'] ?? 0,
      failedRequests: requestCounts['failed'] ?? 0,
      interruptedRequests: requestCounts['interrupted'] ?? 0,
      eventCount: eventRows.length,
      toolCallCount: toolCalls.length,
      toolFailureCount: failedToolCalls.length,
      averageToolLatencyMs: latencyAverage,
      eventTypes: Map<String, int>.unmodifiable(eventTypes),
    );
  }
}
