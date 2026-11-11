import 'dart:async';

class SubagentTask {
  const SubagentTask({
    required this.id,
    required this.title,
    required this.prompt,
    this.agentType = 'coder',
    this.dependsOn = const <String>[],
    this.parentTaskId,
    this.depth = 0,
  });

  final String id;
  final String title;
  final String prompt;
  final String agentType;
  final List<String> dependsOn;
  final String? parentTaskId;
  final int depth;
}

class SubagentResult {
  const SubagentResult({
    required this.taskId,
    required this.status,
    this.output,
    this.error,
  });

  final String taskId;
  final String status;
  final String? output;
  final String? error;
}

class SubagentInterrupted implements Exception {
  const SubagentInterrupted([this.message = 'Subagent execution was interrupted.']);
  final String message;
  @override
  String toString() => message;
}

typedef SubagentExecutor = Future<String> Function(
  SubagentTask task,
  Map<String, SubagentResult> dependencyResults,
  bool Function() isCancelled,
);
typedef SubagentEventSink = FutureOr<void> Function(Map<String, Object?> event);

/// Dependency-aware, dynamically extensible orchestration. It owns scheduling,
/// messages and lifecycle events only; all inference and tools remain shared.
class SubagentOrchestrator {
  SubagentOrchestrator({
    required SubagentExecutor execute,
    required SubagentEventSink onEvent,
    required this.parentRequestId,
    required this.conversationId,
    this.maxConcurrency = 1,
    this.maxTasks = 8,
    this.maxDepth = 2,
  })  : _execute = execute,
        _onEvent = onEvent {
    if (maxConcurrency < 1 || maxConcurrency > 8) {
      throw ArgumentError.value(maxConcurrency, 'maxConcurrency', 'Concurrency must be between 1 and 8.');
    }
    if (maxTasks < 1 || maxTasks > 8 || maxDepth < 0 || maxDepth > 2) {
      throw ArgumentError('Dynamic subagent limits are outside the supported safe bounds.');
    }
  }

  final SubagentExecutor _execute;
  final SubagentEventSink _onEvent;
  final String parentRequestId;
  final String conversationId;
  final int maxConcurrency;
  final int maxTasks;
  final int maxDepth;

  bool _cancelRequested = false;
  bool _running = false;
  final Map<String, SubagentTask> _tasks = <String, SubagentTask>{};
  final Map<String, SubagentResult> _results = <String, SubagentResult>{};
  final Set<String> _pending = <String>{};
  final Map<String, Future<void>> _active = <String, Future<void>>{};
  final Map<String, String> _activeTypes = <String, String>{};
  final Set<String> _cancelledTasks = <String>{};
  final Map<String, List<Map<String, Object?>>> _inboxes = {};
  final Map<String, List<Completer<Map<String, Object?>>>> _messageWaiters = {};
  String _goal = '';

  bool get isRunning => _running;
  String get currentGoal => _goal;
  int get taskCount => _tasks.length;

  Future<void> createTask(SubagentTask task, {required String creatorTaskId}) async {
    if (!_running) throw StateError('Dynamic child creation is available only during an active orchestration.');
    if (_tasks.length >= maxTasks) throw StateError('The request reached its maximum of $maxTasks subagents.');
    if (_tasks.containsKey(task.id) || task.id.trim().isEmpty || task.title.trim().isEmpty || task.prompt.trim().isEmpty) {
      throw ArgumentError('Subagent id must be unique and prompt/title must be non-empty.');
    }
    final creator = _tasks[creatorTaskId];
    if (creator == null) throw StateError('Unknown creator subagent: $creatorTaskId');
    if (creator.depth >= maxDepth) throw StateError('Maximum subagent nesting depth ($maxDepth) reached.');
    if (!const {'explore', 'plan', 'coder', 'reviewer'}.contains(task.agentType)) {
      throw ArgumentError('Unsupported subagent role: ${task.agentType}');
    }
    if (task.dependsOn.toSet().length != task.dependsOn.length ||
        task.dependsOn.any((id) => !_tasks.containsKey(id) || id == task.id)) {
      throw ArgumentError('Dependencies must be unique existing tasks and cannot include the new task.');
    }
    final registered = SubagentTask(
      id: task.id,
      title: task.title,
      prompt: task.prompt,
      agentType: task.agentType,
      dependsOn: List<String>.unmodifiable(task.dependsOn),
      parentTaskId: creatorTaskId,
      depth: creator.depth + 1,
    );
    _tasks[registered.id] = registered;
    await _emit(registered, 'subagent_created', 'pending',
        details: 'Created dynamically by $creatorTaskId; waiting for explicit spawn.');
  }

  Future<void> spawnTask(String taskId) async {
    if (!_running) throw StateError('Subagents can only be spawned during active orchestration.');
    final task = _tasks[taskId];
    if (task == null) throw StateError('Unknown subagent: $taskId');
    if (_results.containsKey(taskId) || _active.containsKey(taskId) || _pending.contains(taskId)) {
      throw StateError('Subagent $taskId has already been spawned or completed.');
    }
    for (final dependency in task.dependsOn) {
      final result = _results[dependency];
      if (result == null || result.status != 'completed') {
        throw StateError('Dependency $dependency must complete before $taskId can spawn.');
      }
    }
    _pending.add(taskId);
    await _emit(task, 'subagent_queued', 'pending');
  }

  bool cancelTask(String taskId) {
    if (!_tasks.containsKey(taskId) || _results.containsKey(taskId)) return false;
    _cancelledTasks.add(taskId);
    return true;
  }

  bool isTaskCancelled(String taskId) => _cancelledTasks.contains(taskId);

  Map<String, Object?> status(String taskId) {
    final task = _tasks[taskId];
    if (task == null) return <String, Object?>{'task_id': taskId, 'status': 'not_found'};
    final result = _results[taskId];
    return <String, Object?>{
      'task_id': taskId,
      'title': task.title,
      'agent_type': task.agentType,
      'parent_task_id': task.parentTaskId,
      'depth': task.depth,
      'status': result?.status ?? (_active.containsKey(taskId) ? 'running' : _pending.contains(taskId) ? 'pending' : 'created'),
      if (result?.output != null) 'result': result!.output,
      if (result?.error != null) 'error': result!.error,
    };
  }

  Future<void> sendMessage({
    required String fromTaskId,
    required String toTaskId,
    required String content,
  }) async {
    final message = content.trim();
    if (!_tasks.containsKey(fromTaskId) || message.isEmpty || message.length > 4000) {
      throw ArgumentError('Message sender and content are required; content is limited to 4000 characters.');
    }
    if (toTaskId != 'parent' && !_tasks.containsKey(toTaskId)) {
      throw StateError('Unknown message recipient: $toTaskId');
    }
    final envelope = <String, Object?>{
      'from_task_id': fromTaskId,
      'to_task_id': toTaskId,
      'content': message,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
    final waiters = _messageWaiters[toTaskId];
    if (waiters != null && waiters.isNotEmpty) {
      waiters.removeAt(0).complete(envelope);
    } else {
      (_inboxes[toTaskId] ??= <Map<String, Object?>>[]).add(envelope);
    }
    await _emit(_tasks[fromTaskId]!, 'subagent_message_sent', 'completed',
        details: 'Message sent to $toTaskId.', metadata: envelope);
  }

  Future<Map<String, Object?>?> waitForMessage({
    required String taskId,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!_tasks.containsKey(taskId)) throw StateError('Unknown waiting subagent: $taskId');
    final inbox = _inboxes[taskId];
    if (inbox != null && inbox.isNotEmpty) return inbox.removeAt(0);
    if (timeout <= Duration.zero || timeout > const Duration(seconds: 60)) {
      throw ArgumentError('Message wait timeout must be between 1 and 60 seconds.');
    }
    final waiter = Completer<Map<String, Object?>>();
    (_messageWaiters[taskId] ??= <Completer<Map<String, Object?>>>[]).add(waiter);
    try {
      return await waiter.future.timeout(timeout, onTimeout: () => <String, Object?>{});
    } finally {
      _messageWaiters[taskId]?.remove(waiter);
    }
  }

  Future<void> updateGoal({required String taskId, required String goal}) async {
    if (!_tasks.containsKey(taskId)) throw StateError('Unknown goal editor: $taskId');
    final next = goal.trim();
    if (next.isEmpty || next.length > 2000) throw ArgumentError('Goal must contain 1–2000 characters.');
    _goal = next;
    await _emit(_tasks[taskId]!, 'subagent_goal_updated', 'completed', details: next);
  }

  void cancel() => _cancelRequested = true;

  Future<List<SubagentResult>> run(List<SubagentTask> tasks) async {
    if (_running) throw StateError('This orchestrator is already running.');
    _cancelRequested = false;
    _cancelledTasks.clear();
    _results.clear();
    _tasks.clear();
    _pending.clear();
    _active.clear();
    _activeTypes.clear();
    _inboxes.clear();
    _messageWaiters.clear();
    _goal = '';
    _validate(tasks);
    if (tasks.length > maxTasks) throw ArgumentError('At most $maxTasks subagents are allowed per request.');
    for (final task in tasks) {
      _tasks[task.id] = task;
      _pending.add(task.id);
    }
    _running = true;
    try {
      for (final task in tasks) {
        await _emit(task, 'subagent_created', 'pending');
      }

      Future<void> start(SubagentTask task) async {
        try {
          await _emit(task, 'subagent_started', 'running');
          final dependencies = <String, SubagentResult>{
            for (final id in task.dependsOn) id: _results[id]!,
          };
          final output = await _execute(task, Map.unmodifiable(dependencies),
              () => isTaskCancelled(task.id));
          if (isTaskCancelled(task.id)) {
            _results[task.id] = SubagentResult(taskId: task.id, status: 'cancelled');
            await _emit(task, 'subagent_cancelled', 'cancelled');
          } else {
            _results[task.id] = SubagentResult(taskId: task.id, status: 'completed', output: output);
            final visible = output.length > 1200 ? '${output.substring(0, 1200)}…' : output;
            await _emit(task, 'subagent_completed', 'completed', details: visible, result: output);
          }
        } on SubagentInterrupted catch (error) {
          final cancelled = isTaskCancelled(task.id);
          _results[task.id] = SubagentResult(taskId: task.id,
              status: cancelled ? 'cancelled' : 'interrupted', error: error.message);
          await _emit(task, cancelled ? 'subagent_cancelled' : 'subagent_interrupted',
              cancelled ? 'cancelled' : 'interrupted', details: error.message);
        } catch (error) {
          _results[task.id] = SubagentResult(taskId: task.id, status: 'failed', error: error.toString());
          await _emit(task, 'subagent_failed', 'failed', details: error.toString());
        }
      }

      while (_pending.isNotEmpty || _active.isNotEmpty) {
        if (_cancelRequested) {
          for (final id in _pending.toList()) {
            final task = _tasks[id]!;
            _results[id] = SubagentResult(taskId: id, status: 'cancelled');
            _pending.remove(id);
            await _emit(task, 'subagent_cancelled', 'cancelled');
          }
        } else {
          var scheduled = false;
          for (final task in _tasks.values.toList(growable: false)) {
            if (_active.length >= maxConcurrency) break;
            if (!_pending.contains(task.id)) continue;
            if (_activeTypes.values.contains('coder') ||
                (task.agentType == 'coder' && _active.isNotEmpty)) continue;
            if (_cancelledTasks.contains(task.id)) {
              _pending.remove(task.id);
              _results[task.id] = SubagentResult(taskId: task.id, status: 'cancelled');
              await _emit(task, 'subagent_cancelled', 'cancelled');
              scheduled = true;
              continue;
            }
            final dependencies = task.dependsOn.map((id) => _results[id]).toList();
            if (dependencies.any((result) => result != null && result.status != 'completed')) {
              _pending.remove(task.id);
              _results[task.id] = SubagentResult(taskId: task.id, status: 'skipped');
              await _emit(task, 'subagent_skipped', 'interrupted',
                  details: 'تعذر التنفيذ بسبب عدم اكتمال إحدى المهام السابقة.');
              scheduled = true;
              continue;
            }
            if (dependencies.any((result) => result == null)) continue;
            _pending.remove(task.id);
            _activeTypes[task.id] = task.agentType;
            _active[task.id] = start(task);
            scheduled = true;
          }
          if (!scheduled && _active.isEmpty && _pending.isNotEmpty) {
            throw StateError('Subagent graph cannot make progress.');
          }
        }
        if (_active.isNotEmpty) {
          await Future.any(_active.values);
          final finished = _active.keys.where(_results.containsKey).toList();
          for (final id in finished) {
            _active.remove(id);
            _activeTypes.remove(id);
          }
        }
      }
      return _tasks.keys.map((id) => _results[id] ?? SubagentResult(taskId: id, status: 'created')).toList(growable: false);
    } finally {
      _running = false;
    }
  }

  Future<void> _emit(SubagentTask task, String type, String status,
      {String? details, String? result, Map<String, Object?> metadata = const <String, Object?>{}}) async {
    try {
      await _onEvent(<String, Object?>{
        'id': 'subagent_${parentRequestId}_${task.id}_${type}_${DateTime.now().microsecondsSinceEpoch}',
        'request_id': parentRequestId,
        'session_id': conversationId,
        'task_id': task.id,
        'agent_type': task.agentType,
        'title': task.title,
        'task_prompt': task.prompt,
        'depends_on': task.dependsOn,
        if (task.parentTaskId != null) 'parent_task_id': task.parentTaskId,
        'depth': task.depth,
        ...metadata,
        'type': type,
        'status': status,
        if (details != null) 'details': details,
        if (result != null) 'result': result,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {
      // A timeline sink must never strand a worker or corrupt task scheduling.
    }
  }

  void _validate(List<SubagentTask> tasks) {
    final ids = <String>{};
    for (final task in tasks) {
      if (task.id.trim().isEmpty || task.prompt.trim().isEmpty) throw ArgumentError('Subagent ids and prompts must not be empty.');
      if (!ids.add(task.id)) throw ArgumentError('Duplicate subagent id: ${task.id}');
      if (!const {'explore', 'plan', 'coder', 'reviewer'}.contains(task.agentType)) throw ArgumentError('Unknown subagent type: ${task.agentType}');
    }
    for (final task in tasks) {
      for (final dependency in task.dependsOn) {
        if (!ids.contains(dependency) || dependency == task.id) throw ArgumentError('Unknown or self dependency $dependency for ${task.id}.');
      }
    }
    final visited = <String>{};
    final visiting = <String>{};
    void visit(String id) {
      if (visiting.contains(id)) throw ArgumentError('Subagent dependency cycle includes $id.');
      if (visited.contains(id)) return;
      visiting.add(id);
      for (final dependency in _tasks.containsKey(id) ? _tasks[id]!.dependsOn : tasks.firstWhere((t) => t.id == id).dependsOn) {
        visit(dependency);
      }
      visiting.remove(id);
      visited.add(id);
    }
    final byId = {for (final task in tasks) task.id: task};
    for (final task in tasks) {
      for (final dependency in task.dependsOn) {
        if (!byId.containsKey(dependency)) throw ArgumentError('Unknown dependency $dependency for ${task.id}.');
      }
    }
    for (final task in tasks) visit(task.id);
  }
}
