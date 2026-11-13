import 'dart:async';

typedef SubagentLifecycleEventSink = FutureOr<void> Function(
  Map<String, Object?> event,
);
typedef LoadSubagentRuntimeState = Future<Map<String, Object?>?> Function(String requestId);
typedef SaveSubagentRuntimeState = Future<void> Function(String requestId, Map<String, Object?> state);

class DynamicSubagentRecord {
  DynamicSubagentRecord({
    required this.id,
    required this.taskId,
    required this.parentRequestId,
    required this.conversationId,
    required this.title,
    required this.prompt,
    required this.agentType,
    required this.dependsOn,
    this.status = 'idle',
    this.progressPercent,
    this.result,
    this.error,
    this.dismissed = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toUtc();

  final String id;
  final String taskId;
  final String parentRequestId;
  final String conversationId;
  final String title;
  final String prompt;
  final String agentType;
  final List<String> dependsOn;
  final DateTime createdAt;
  String status;
  int? progressPercent;
  String? result;
  String? error;
  bool dismissed;

  String get wireStatus => switch (status) {
        'idle' => 'STATUS_IDLE',
        'pending' => 'STATUS_PENDING',
        'running' => 'STATUS_RUNNING',
        'completed' || 'failed' || 'interrupted' || 'cancelled' || 'deleted' =>
          'STATUS_TERMINATED',
        _ => 'STATUS_UNSPECIFIED',
      };

  factory DynamicSubagentRecord.fromMap(Map<String, dynamic> map) =>
      DynamicSubagentRecord(
        id: map['id']?.toString() ?? '',
        taskId: map['task_id']?.toString() ?? '',
        parentRequestId: map['parent_request_id']?.toString() ?? '',
        conversationId: map['conversation_id']?.toString() ?? 'global',
        title: map['title']?.toString() ?? '',
        prompt: map['prompt']?.toString() ?? '',
        agentType: map['agent_type']?.toString() ?? 'explore',
        dependsOn: (map['depends_on'] as List? ?? const <dynamic>[])
            .map((item) => item.toString()).toList(growable: false),
        status: map['status']?.toString() ?? 'idle',
        progressPercent: map['progress_percent'] as int?,
        result: map['result']?.toString(),
        error: map['error']?.toString(),
        dismissed: map['dismissed'] == true,
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'task_id': taskId,
        'parent_request_id': parentRequestId,
        'conversation_id': conversationId,
        'title': title,
        'prompt': prompt,
        'agent_type': agentType,
        'depends_on': List<String>.unmodifiable(dependsOn),
        'status': status,
        'wire_status': wireStatus,
        'progress_percent': progressPercent,
        'result': result,
        'error': error,
        'dismissed': dismissed,
        'created_at': createdAt.toIso8601String(),
      };
}

/// Request-scoped dynamic subagent lifecycle, mailbox and goal state.
///
/// This is an original Giant Agent contract informed by the observed Kimi
/// lifecycle vocabulary. It does not copy Kimi handlers or assume undocumented
/// remote argument schemas.
class SubagentLifecycleManager {
  SubagentLifecycleManager({
    required SubagentLifecycleEventSink onEvent,
    LoadSubagentRuntimeState? loadState,
    SaveSubagentRuntimeState? saveState,
  })  : _onEvent = onEvent,
        _loadState = loadState,
        _saveState = saveState;

  final SubagentLifecycleEventSink _onEvent;
  final LoadSubagentRuntimeState? _loadState;
  final SaveSubagentRuntimeState? _saveState;
  final Set<String> _restoredRequests = <String>{};
  final Map<String, Map<String, DynamicSubagentRecord>> _requests = {};
  final Map<String, List<Map<String, Object?>>> _mailboxes = {};
  final Map<String, List<Completer<void>>> _messageWaiters = {};
  final Map<String, String> _goals = {};

  static const int maxChildrenPerRequest = 6;
  static const int maxMailboxMessages = 100;

  /// Restores request-scoped goal and pending messages before the request is used.
  /// Call once after process start; subsequent calls are idempotent.
  Future<void> restoreRequest(String requestId) async {
    if (requestId.trim().isEmpty || _restoredRequests.contains(requestId)) return;
    final state = await _loadState?.call(requestId);
    if (state != null) {
      final goal = state['current_goal']?.toString();
      if (goal != null && goal.isNotEmpty) _goals[requestId] = goal;
      final rawRecords = state['records'];
      if (rawRecords is Map) {
        final restored = <String, DynamicSubagentRecord>{};
        for (final entry in rawRecords.entries) {
          if (entry.value is! Map) continue;
          final record = DynamicSubagentRecord.fromMap(
            Map<String, dynamic>.from(entry.value as Map),
          );
          if (record.id.isNotEmpty && record.parentRequestId == requestId) {
            restored[record.id] = record;
          }
        }
        if (restored.isNotEmpty) _requests[requestId] = restored;
      }
      final rawMailboxes = state['mailboxes'];
      if (rawMailboxes is Map) {
        for (final entry in rawMailboxes.entries) {
          final agentId = entry.key.toString();
          final rawMessages = entry.value;
          if (agentId.isEmpty || rawMessages is! List) continue;
          final messages = rawMessages.whereType<Map>().take(maxMailboxMessages)
              .map((item) => Map<String, Object?>.from(item)).toList();
          if (messages.isNotEmpty) _mailboxes[_key(requestId, agentId)] = messages;
        }
      }
    }
    _restoredRequests.add(requestId);
  }

  Future<void> _persistRequest(String requestId) async {
    final save = _saveState;
    if (save == null) return;
    final mailboxes = <String, Object?>{};
    final records = <String, Object?>{
      for (final entry in (_requests[requestId] ?? const <String, DynamicSubagentRecord>{}).entries)
        entry.key: entry.value.toMap(),
    };
    final prefix = '$requestId::';
    for (final entry in _mailboxes.entries) {
      if (entry.key.startsWith(prefix) && entry.value.isNotEmpty) {
        mailboxes[entry.key.substring(prefix.length)] =
            entry.value.map((message) => Map<String, Object?>.from(message)).toList();
      }
    }
    await save(requestId, <String, Object?>{
      'current_goal': _goals[requestId],
      'records': records,
      'mailboxes': mailboxes,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  String _key(String requestId, String agentId) => '$requestId::$agentId';

  Future<DynamicSubagentRecord> create({
    required String requestId,
    required String conversationId,
    required String id,
    required String title,
    required String prompt,
    required String agentType,
    List<String> dependsOn = const <String>[],
    String? creatorTaskId,
  }) async {
    await restoreRequest(requestId);
    if (requestId.trim().isEmpty ||
        conversationId.trim().isEmpty ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,48}$').hasMatch(id)) {
      throw ArgumentError('A valid parent request, conversation and agent id are required.');
    }
    if (creatorTaskId != null && creatorTaskId.isNotEmpty) {
      throw StateError('A child agent cannot create another child agent.');
    }
    if (title.trim().isEmpty || title.length > 100 ||
        prompt.trim().isEmpty || prompt.length > 1200) {
      throw ArgumentError('Subagent title or prompt is empty or exceeds its limit.');
    }
    if (!const {'explore', 'plan', 'coder', 'reviewer'}.contains(agentType)) {
      throw ArgumentError.value(agentType, 'agentType', 'Unknown subagent role.');
    }
    if (dependsOn.toSet().length != dependsOn.length || dependsOn.contains(id)) {
      throw ArgumentError('Subagent dependencies must be unique and cannot include itself.');
    }
    final children = _requests.putIfAbsent(requestId, () => <String, DynamicSubagentRecord>{});
    if (children.containsKey(id)) throw StateError('Duplicate subagent id: $id');
    if (children.length >= maxChildrenPerRequest) {
      throw StateError('A request may create at most $maxChildrenPerRequest dynamic subagents.');
    }
    for (final dependencyId in dependsOn) {
      if (!children.containsKey(dependencyId)) {
        throw ArgumentError('Unknown subagent dependency: $dependencyId');
      }
    }
    final record = DynamicSubagentRecord(
      id: id,
      taskId: '${requestId}_dynamic_$id',
      parentRequestId: requestId,
      conversationId: conversationId,
      title: title.trim(),
      prompt: prompt.trim(),
      agentType: agentType,
      dependsOn: List<String>.unmodifiable(dependsOn),
    );
    children[id] = record;
    await _persistRequest(requestId);
    await _emit(record, 'subagent_created', details: 'تم تسجيل الوكيل؛ لم يبدأ التنفيذ بعد.');
    return record;
  }

  DynamicSubagentRecord? get(String requestId, String agentId) =>
      _requests[requestId]?[agentId];

  List<DynamicSubagentRecord> forRequest(String requestId) =>
      List<DynamicSubagentRecord>.unmodifiable(
        _requests[requestId]?.values ?? const <DynamicSubagentRecord>[],
      );

  Future<List<Map<String, Object?>>> drainMessages(String requestId, String agentId) async {
    await restoreRequest(requestId);
    final key = _key(requestId, agentId);
    final mailbox = _mailboxes[key];
    if (mailbox == null || mailbox.isEmpty) return const <Map<String, Object?>>[];
    final messages = List<Map<String, Object?>>.unmodifiable(mailbox);
    mailbox.clear();
    await _persistRequest(requestId);
    return messages;
  }

  String? currentGoal(String requestId) => _goals[requestId];

  Future<void> start(String requestId, String agentId) async {
    await restoreRequest(requestId);
    final record = _require(requestId, agentId);
    if (record.dismissed) throw StateError('Subagent was dismissed.');
    if (record.status != 'idle' && record.status != 'pending') {
      throw StateError('Only an idle or pending subagent can be spawned.');
    }
    for (final dependencyId in record.dependsOn) {
      final dependency = _require(requestId, dependencyId);
      if (dependency.status != 'completed') {
        throw StateError('Dependency $dependencyId has not completed.');
      }
    }
    record
      ..status = 'running'
      ..progressPercent = null
      ..error = null;
    await _persistRequest(requestId);
    await _emit(record, 'subagent_started');
  }

  Future<void> complete(String requestId, String agentId, String result) async {
    await restoreRequest(requestId);
    final record = _require(requestId, agentId);
    if (record.status != 'running') throw StateError('Subagent is not running.');
    if (result.trim().isEmpty) throw StateError('A completed subagent must return a non-empty result.');
    record
      ..status = 'completed'
      ..progressPercent = 100
      ..result = result
      ..error = null;
    await _persistRequest(requestId);
    await _emit(record, 'subagent_completed',
        details: result.length > 1200 ? '${result.substring(0, 1200)}…' : result,
        result: result);
  }

  Future<void> fail(
    String requestId,
    String agentId,
    Object error, {
    bool interrupted = false,
  }) async {
    final record = _require(requestId, agentId);
    if (record.status != 'running') return;
    record
      ..status = interrupted ? 'interrupted' : 'failed'
      ..error = error.toString();
    await _persistRequest(requestId);
    await _emit(
      record,
      interrupted ? 'subagent_interrupted' : 'subagent_failed',
      details: error.toString(),
    );
  }

  Future<void> delete(String requestId, String agentId) async {
    await restoreRequest(requestId);
    final record = _require(requestId, agentId);
    if (record.status == 'running') {
      throw StateError('A running subagent cannot be deleted; interrupt it first.');
    }
    if (record.dismissed) return;
    if (record.status == 'idle' || record.status == 'pending') {
      record.status = 'cancelled';
      await _emit(record, 'subagent_cancelled', details: 'أُلغي الوكيل قبل بدء التنفيذ.');
    }
    record.dismissed = true;
    await _persistRequest(requestId);
    await _emit(record, 'subagent_dismissed',
        details: 'أُخفي الوكيل من الإدارة مع الاحتفاظ بسجل التدقيق.');
  }

  Future<void> sendMessage({
    required String requestId,
    required String agentId,
    required String message,
    String? senderTaskId,
  }) async {
    await restoreRequest(requestId);
    final record = _require(requestId, agentId);
    if (record.dismissed) throw StateError('Cannot message a dismissed subagent.');
    final normalized = message.trim();
    if (normalized.isEmpty || normalized.length > 4000) {
      throw ArgumentError('Message must contain 1 to 4000 characters.');
    }
    final item = <String, Object?>{
      'message': normalized,
      'sender_task_id': senderTaskId,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
    final key = _key(requestId, agentId);
    final mailbox = _mailboxes.putIfAbsent(key, () => <Map<String, Object?>>[]);
    if (mailbox.length >= maxMailboxMessages) {
      throw StateError('Subagent mailbox is full; consume pending messages before sending more.');
    }
    mailbox.add(item);
    await _persistRequest(requestId);
    final waiters = _messageWaiters[key];
    if (waiters != null && waiters.isNotEmpty) {
      final waiter = waiters.removeAt(0);
      if (!waiter.isCompleted) waiter.complete();
    }
    await _emit(record, 'subagent_message_sent',
        details: normalized.length > 500 ? '${normalized.substring(0, 500)}…' : normalized);
  }

  Future<Map<String, Object?>?> waitForMessage({
    required String requestId,
    required String agentId,
    required int timeoutSeconds,
    bool Function()? isCancelled,
  }) async {
    await restoreRequest(requestId);
    final record = _require(requestId, agentId);
    if (timeoutSeconds < 1 || timeoutSeconds > 30) {
      throw ArgumentError.value(timeoutSeconds, 'timeoutSeconds', 'Timeout must be 1–30 seconds.');
    }
    final key = _key(requestId, agentId);
    final mailbox = _mailboxes.putIfAbsent(key, () => <Map<String, Object?>>[]);
    if (mailbox.isNotEmpty) {
      final message = mailbox.removeAt(0);
      await _persistRequest(requestId);
      return message;
    }
    final waiter = Completer<void>();
    final waiters = _messageWaiters.putIfAbsent(key, () => <Completer<void>>[]);
    waiters.add(waiter);
    final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds));
    try {
      while (!waiter.isCompleted && DateTime.now().isBefore(deadline)) {
        if (isCancelled?.call() == true) {
          throw StateError('Subagent mailbox wait was cancelled.');
        }
        await Future.any<void>([
          waiter.future,
          Future<void>.delayed(const Duration(milliseconds: 100)),
        ]);
      }
      if (isCancelled?.call() == true) {
        throw StateError('Subagent mailbox wait was cancelled.');
      }
      if (!waiter.isCompleted) return null;
    } finally {
      waiters.remove(waiter);
      if (waiters.isEmpty) _messageWaiters.remove(key);
    }
    if (mailbox.isEmpty) return null;
    final message = mailbox.removeAt(0);
    await _persistRequest(requestId);
    await _emit(record, 'subagent_message_received',
        details: message['message']?.toString());
    return message;
  }

  /// Persists a truthful progress snapshot for a running child.
  /// 100 is reserved for complete(); callers may report 0..99 while running.
  Future<void> updateProgress(
    String requestId,
    String agentId,
    int progressPercent, {
    String? details,
  }) async {
    await restoreRequest(requestId);
    if (progressPercent < 0 || progressPercent > 99) {
      throw ArgumentError.value(progressPercent, 'progressPercent',
          'Progress updates must be between 0 and 99; completion owns 100.');
    }
    final record = _require(requestId, agentId);
    if (record.status != 'running') {
      throw StateError('Progress can only be updated for a running subagent.');
    }
    record.progressPercent = progressPercent;
    await _persistRequest(requestId);
    await _emit(record, 'subagent_progress',
        details: details == null || details.trim().isEmpty
            ? 'التقدم: $progressPercent%'
            : details.trim().substring(0, details.trim().length.clamp(0, 500)));
  }

  Future<void> updateGoal(String requestId, String goal) async {
    await restoreRequest(requestId);
    final normalized = goal.trim();
    if (requestId.trim().isEmpty || normalized.isEmpty || normalized.length > 2000) {
      throw ArgumentError('Updated goal must contain 1 to 2000 characters.');
    }
    _goals[requestId] = normalized;
    await _persistRequest(requestId);
    await _onEvent(<String, Object?>{
      'id': 'goal_updated_${requestId}_${DateTime.now().microsecondsSinceEpoch}',
      'request_id': requestId,
      'type': 'goal_updated',
      'status': 'completed',
      'title': 'تم تحديث هدف المهمة',
      'details': normalized,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });
  }

  DynamicSubagentRecord _require(String requestId, String agentId) {
    final record = get(requestId, agentId);
    if (record == null) throw StateError('Subagent not found: $agentId');
    return record;
  }

  Future<void> _emit(
    DynamicSubagentRecord record,
    String type, {
    String? details,
    String? result,
  }) =>
      Future<void>.sync(() => _onEvent(<String, Object?>{
            'id': '${type}_${record.parentRequestId}_${record.id}_${DateTime.now().microsecondsSinceEpoch}',
            'request_id': record.parentRequestId,
            'session_id': record.conversationId,
            'chat_id': record.conversationId,
            'agent_id': record.taskId,
            'task_id': record.taskId,
            'agent_type': record.agentType,
            'title': record.title,
            'task_prompt': record.prompt,
            'depends_on': record.dependsOn.map((id) => '${record.parentRequestId}_dynamic_$id').toList(growable: false),
            'type': type,
            'status': record.status,
            'wire_status': record.wireStatus,
            'progress_percent': record.progressPercent,
            if (details != null) 'details': details,
            if (result != null) 'result': result,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          }));
}
