import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'dart:async';
import 'dart:math';

enum TimelineEventType {
  taskStarted, taskCompleted, taskFailed, taskCancelled,
  agentCreated, agentStarted, agentProgress, agentCompleted, agentFailed,
  toolStarted, toolProgress, toolCompleted, toolFailed, toolCancelled,
  message, info, warning, error,
}

enum TimelineStatus { pending, waiting, running, completed, failed, cancelled }

String timelineNewId([String prefix = 'evt']) {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_$hex';
}

class AgentTimelineEvent {
  const AgentTimelineEvent({
    required this.id,
    required this.sessionId,
    required this.type,
    required this.title,
    required this.status,
    required this.createdAt,
    this.description,
    this.agentId,
    this.parentAgentId,
    this.toolCallId,
    this.toolName,
    this.progress,
    this.error,
    this.metadata = const {},
    this.completedAt,
  });

  final String id;
  final String sessionId;
  final TimelineEventType type;
  final String title;
  final TimelineStatus status;
  final DateTime createdAt;
  final String? description;
  final String? agentId;
  final String? parentAgentId;
  final String? toolCallId;
  final String? toolName;
  final double? progress;
  final String? error;
  final Map<String, dynamic> metadata;
  final DateTime? completedAt;

  bool get isTerminal => status == TimelineStatus.completed ||
      status == TimelineStatus.failed || status == TimelineStatus.cancelled;
  bool get isActive => status == TimelineStatus.running ||
      status == TimelineStatus.waiting || status == TimelineStatus.pending;

  AgentTimelineEvent copyWith({
    String? title,
    TimelineStatus? status,
    Object? description = _unset,
    Object? agentId = _unset,
    Object? parentAgentId = _unset,
    Object? toolCallId = _unset,
    Object? toolName = _unset,
    Object? progress = _unset,
    Object? error = _unset,
    Map<String, dynamic>? metadata,
    Object? completedAt = _unset,
  }) => AgentTimelineEvent(
    id: id, sessionId: sessionId, type: type, title: title ?? this.title,
    status: status ?? this.status, createdAt: createdAt,
    description: identical(description, _unset) ? this.description : description as String?,
    agentId: identical(agentId, _unset) ? this.agentId : agentId as String?,
    parentAgentId: identical(parentAgentId, _unset) ? this.parentAgentId : parentAgentId as String?,
    toolCallId: identical(toolCallId, _unset) ? this.toolCallId : toolCallId as String?,
    toolName: identical(toolName, _unset) ? this.toolName : toolName as String?,
    progress: identical(progress, _unset) ? this.progress : progress as double?,
    error: identical(error, _unset) ? this.error : error as String?,
    metadata: metadata ?? this.metadata,
    completedAt: identical(completedAt, _unset) ? this.completedAt : completedAt as DateTime?,
  );

  Map<String, Object?> toMap() => {
    'id': id, 'session_id': sessionId, 'type': type.name, 'title': title,
    'status': status.name, 'created_at': createdAt.millisecondsSinceEpoch,
    'description': description, 'agent_id': agentId,
    'parent_agent_id': parentAgentId, 'tool_call_id': toolCallId,
    'tool_name': toolName, 'progress': progress, 'error': error,
    'metadata_json': _encodeMetadata(metadata),
    'completed_at': completedAt?.millisecondsSinceEpoch,
  };

  factory AgentTimelineEvent.fromMap(Map<String, Object?> map) {
    final rawMetadata = map['metadata_json']?.toString();
    Map<String, dynamic> metadata = {};
    if (rawMetadata != null && rawMetadata.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawMetadata);
        if (decoded is Map) metadata = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return AgentTimelineEvent(
      id: map['id'].toString(), sessionId: map['session_id'].toString(),
      type: _enumByName(TimelineEventType.values, map['type'], TimelineEventType.info),
      title: map['title']?.toString() ?? '',
      status: _enumByName(TimelineStatus.values, map['status'], TimelineStatus.pending),
      createdAt: DateTime.fromMillisecondsSinceEpoch(_asInt(map['created_at'])),
      description: map['description']?.toString(), agentId: map['agent_id']?.toString(),
      parentAgentId: map['parent_agent_id']?.toString(),
      toolCallId: map['tool_call_id']?.toString(), toolName: map['tool_name']?.toString(),
      progress: map['progress'] == null ? null : (map['progress'] as num).toDouble(),
      error: map['error']?.toString(), metadata: metadata,
      completedAt: map['completed_at'] == null ? null :
        DateTime.fromMillisecondsSinceEpoch(_asInt(map['completed_at'])),
    );
  }
}

const Object _unset = Object();

String _encodeMetadata(Map<String, dynamic> value) {
  try { return jsonEncode(value); } catch (_) { return '{}'; }
}
int _asInt(Object? value) => value is num ? value.toInt() : int.tryParse(value.toString()) ?? 0;
T _enumByName<T extends Enum>(List<T> values, Object? value, T fallback) {
  final name = value?.toString();
  for (final item in values) { if (item.name == name) return item; }
  return fallback;
}

class TimelineEventBus {
  TimelineEventBus();
  final StreamController<AgentTimelineEvent> _controller =
      StreamController<AgentTimelineEvent>.broadcast(sync: true);
  bool _closed = false;
  Stream<AgentTimelineEvent> get stream => _controller.stream;
  void emit(AgentTimelineEvent event) {
    if (!_closed) _controller.add(event);
  }
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _controller.close();
  }
}

class TimelineEngine {
  TimelineEngine({required this.sessionId, TimelineEventBus? bus})
      : bus = bus ?? TimelineEventBus();

  final String sessionId;
  final TimelineEventBus bus;
  final List<AgentTimelineEvent> _events = [];
  final StreamController<List<AgentTimelineEvent>> _changes =
      StreamController<List<AgentTimelineEvent>>.broadcast();
  bool _disposed = false;

  List<AgentTimelineEvent> get events => List.unmodifiable(_events);
  Stream<List<AgentTimelineEvent>> get changes => _changes.stream;
  bool get isRunning => _events.any((e) => e.isActive);

  AgentTimelineEvent add({
    required TimelineEventType type,
    required String title,
    TimelineStatus status = TimelineStatus.pending,
    String? description, String? agentId, String? parentAgentId,
    String? toolCallId, String? toolName, double? progress,
    Map<String, dynamic> metadata = const {},
  }) {
    _ensureAlive();
    final event = AgentTimelineEvent(
      id: timelineNewId(), sessionId: sessionId, type: type, title: title,
      status: status, createdAt: DateTime.now(), description: description,
      agentId: agentId, parentAgentId: parentAgentId, toolCallId: toolCallId,
      toolName: toolName, progress: _safeProgress(progress), metadata: metadata,
    );
    _events.add(event);
    _publish(event);
    return event;
  }

  void restore(Iterable<AgentTimelineEvent> events) {
    _ensureAlive();
    _events
      ..clear()
      ..addAll(events.where((e) => e.sessionId == sessionId)
        .toList()..sort((a, b) {
          final byTime = a.createdAt.compareTo(b.createdAt);
          return byTime != 0 ? byTime : a.id.compareTo(b.id);
        }));
    _changes.add(this.events);
  }

  AgentTimelineEvent? update(String id, {
    String? title, TimelineStatus? status, Object? description = _unset,
    Object? progress = _unset, Object? error = _unset,
    Map<String, dynamic>? metadata, Object? completedAt = _unset,
  }) {
    _ensureAlive();
    final index = _events.indexWhere((e) => e.id == id);
    if (index < 0) return null;
    final old = _events[index];
    final nextStatus = status ?? old.status;
    final rawProgress = identical(progress, _unset)
        ? old.progress
        : progress == null ? null : (progress as num).toDouble();
    final terminal = nextStatus == TimelineStatus.completed ||
        nextStatus == TimelineStatus.failed || nextStatus == TimelineStatus.cancelled;
    final updated = old.copyWith(
      title: title, status: nextStatus, description: description,
      progress: rawProgress == null ? null : _safeProgress(rawProgress),
      error: error, metadata: metadata,
      completedAt: terminal
          ? (identical(completedAt, _unset) ? DateTime.now() : completedAt)
          : null,
    );
    _events[index] = updated;
    _publish(updated);
    return updated;
  }

  int cancelByToolCallId(String toolCallId, {String reason = 'Cancelled'}) {
    _ensureAlive();
    var count = 0;
    for (var i = 0; i < _events.length; i++) {
      final event = _events[i];
      if (event.toolCallId == toolCallId && event.isActive) {
        final updated = event.copyWith(
          status: TimelineStatus.cancelled, error: reason,
          completedAt: DateTime.now(),
        );
        _events[i] = updated;
        _publish(updated);
        count++;
      }
    }
    return count;
  }

  void _publish(AgentTimelineEvent event) {
    bus.emit(event);
    _changes.add(events);
  }
  double? _safeProgress(double? value) {
    if (value == null || !value.isFinite) return null;
    return value.clamp(0.0, 1.0).toDouble();
  }
  void _ensureAlive() {
    if (_disposed) throw StateError('TimelineEngine is disposed');
  }
  Future<void> dispose({bool closeBus = true}) async {
    if (_disposed) return;
    _disposed = true;
    await _changes.close();
    if (closeBus) await bus.close();
  }
}
