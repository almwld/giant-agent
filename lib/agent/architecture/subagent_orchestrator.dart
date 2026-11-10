import 'dart:async';

class SubagentTask {
  const SubagentTask({
    required this.id,
    required this.title,
    required this.prompt,
    this.agentType = 'coder',
    this.dependsOn = const <String>[],
  });

  final String id;
  final String title;
  final String prompt;
  final String agentType;
  final List<String> dependsOn;
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

/// Dependency-aware orchestration over the application's existing runtime.
/// It owns task coordination only; model, terminal and tool runtimes are shared.
class SubagentOrchestrator {
  SubagentOrchestrator({
    required SubagentExecutor execute,
    required SubagentEventSink onEvent,
    required this.parentRequestId,
    required this.conversationId,
    this.maxConcurrency = 1,
  })  : _execute = execute,
        _onEvent = onEvent {
    if (maxConcurrency < 1 || maxConcurrency > 8) {
      throw ArgumentError.value(
        maxConcurrency,
        'maxConcurrency',
        'Concurrency must be between 1 and 8.',
      );
    }
  }

  final SubagentExecutor _execute;
  final SubagentEventSink _onEvent;
  final String parentRequestId;
  final String conversationId;
  final int maxConcurrency;
  bool _cancelRequested = false;
  final Set<String> _knownTaskIds = <String>{};
  final Set<String> _finishedTaskIds = <String>{};
  final Set<String> _cancelledTasks = <String>{};

  void cancel() => _cancelRequested = true;

  bool cancelTask(String taskId) {
    if (!_knownTaskIds.contains(taskId) || _finishedTaskIds.contains(taskId)) {
      return false;
    }
    _cancelledTasks.add(taskId);
    return true;
  }

  bool isTaskCancelled(String taskId) => _cancelledTasks.contains(taskId);

  Future<List<SubagentResult>> run(List<SubagentTask> tasks) async {
    _cancelRequested = false;
    _cancelledTasks.clear();
    _finishedTaskIds.clear();
    _validate(tasks);
    _knownTaskIds
      ..clear()
      ..addAll(tasks.map((task) => task.id));
    final byId = {for (final task in tasks) task.id: task};
    final pending = tasks.map((task) => task.id).toSet();
    final results = <String, SubagentResult>{};
    final active = <String, Future<void>>{};

    Future<void> start(SubagentTask task) async {
      try {
        await _emit(task, 'subagent_started', 'running');
        final dependencies = <String, SubagentResult>{
          for (final id in task.dependsOn) id: results[id]!,
        };
        final output = await _execute(
          task,
          Map.unmodifiable(dependencies),
          () => isTaskCancelled(task.id),
        );
        if (isTaskCancelled(task.id)) {
          results[task.id] = SubagentResult(taskId: task.id, status: 'cancelled');
          await _emit(task, 'subagent_cancelled', 'interrupted');
        } else {
          results[task.id] = SubagentResult(
            taskId: task.id,
            status: 'completed',
            output: output,
          );
          final visibleOutput = output.length > 1200
              ? '${output.substring(0, 1200)}…'
              : output;
          await _emit(
            task,
            'subagent_completed',
            'completed',
            details: visibleOutput,
          );
        }
      } on SubagentInterrupted catch (error) {
        final cancelled = isTaskCancelled(task.id);
        results[task.id] = SubagentResult(
          taskId: task.id,
          status: cancelled ? 'cancelled' : 'interrupted',
          error: error.message,
        );
        await _emit(
          task,
          cancelled ? 'subagent_cancelled' : 'subagent_interrupted',
          'interrupted',
          details: error.message,
        );
      } catch (error) {
        results[task.id] = SubagentResult(
          taskId: task.id,
          status: 'failed',
          error: error.toString(),
        );
        await _emit(task, 'subagent_failed', 'failed',
            details: error.toString());
      } finally {
        _finishedTaskIds.add(task.id);
      }
    }

    while (pending.isNotEmpty || active.isNotEmpty) {
      if (_cancelRequested) {
        for (final id in pending.toList()) {
          final task = byId[id]!;
          results[id] = SubagentResult(taskId: id, status: 'cancelled');
          pending.remove(id);
          await _emit(task, 'subagent_cancelled', 'interrupted');
        }
      } else {
        var scheduled = false;
        for (final task in tasks) {
          if (active.length >= maxConcurrency) break;
          if (!pending.contains(task.id)) continue;
          if (_cancelledTasks.contains(task.id)) {
            pending.remove(task.id);
            results[task.id] = SubagentResult(taskId: task.id, status: 'cancelled');
            await _emit(task, 'subagent_cancelled', 'interrupted');
            _finishedTaskIds.add(task.id);
            scheduled = true;
            continue;
          }
          final dependencyResults =
              task.dependsOn.map((id) => results[id]).toList();
          if (dependencyResults.any(
            (result) => result != null && result.status != 'completed',
          )) {
            pending.remove(task.id);
            results[task.id] =
                SubagentResult(taskId: task.id, status: 'skipped');
            await _emit(
              task,
              'subagent_skipped',
              'interrupted',
              details: 'تعذر التنفيذ بسبب عدم اكتمال إحدى المهام السابقة.',
            );
            _finishedTaskIds.add(task.id);
            scheduled = true;
            continue;
          }
          if (dependencyResults.any((result) => result == null)) continue;
          pending.remove(task.id);
          await _emit(task, 'subagent_queued', 'pending');
          active[task.id] = start(task);
          scheduled = true;
        }
        if (!scheduled && active.isEmpty && pending.isNotEmpty) {
          throw StateError('Subagent graph cannot make progress.');
        }
      }

      if (active.isNotEmpty) {
        await Future.any(active.values);
        final finished = active.keys.where(results.containsKey).toList();
        for (final id in finished) {
          active.remove(id);
        }
      }
    }

    return tasks.map((task) => results[task.id]!).toList(growable: false);
  }

  Future<void> _emit(
    SubagentTask task,
    String type,
    String status, {
    String? details,
  }) async {
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
        'type': type,
        'status': status,
        if (details != null) 'details': details,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {
      // A timeline sink must never strand a worker or corrupt task scheduling.
    }
  }

  void _validate(List<SubagentTask> tasks) {
    final ids = <String>{};
    for (final task in tasks) {
      if (task.id.trim().isEmpty || task.prompt.trim().isEmpty) {
        throw ArgumentError('Subagent ids and prompts must not be empty.');
      }
      if (!ids.add(task.id)) {
        throw ArgumentError('Duplicate subagent id: ${task.id}');
      }
      if (!const {'explore', 'plan', 'coder', 'reviewer'}
          .contains(task.agentType)) {
        throw ArgumentError('Unknown subagent type: ${task.agentType}');
      }
    }
    for (final task in tasks) {
      for (final dependency in task.dependsOn) {
        if (!ids.contains(dependency)) {
          throw ArgumentError(
            'Unknown dependency $dependency for subagent ${task.id}.',
          );
        }
        if (dependency == task.id) {
          throw ArgumentError('A subagent cannot depend on itself.');
        }
      }
    }

    final visited = <String>{};
    final visiting = <String>{};
    void visit(String id) {
      if (visiting.contains(id)) {
        throw ArgumentError('Subagent dependency cycle includes $id.');
      }
      if (visited.contains(id)) return;
      visiting.add(id);
      for (final dependency
          in tasks.firstWhere((task) => task.id == id).dependsOn) {
        visit(dependency);
      }
      visiting.remove(id);
      visited.add(id);
    }

    for (final task in tasks) {
      visit(task.id);
    }
  }
}
