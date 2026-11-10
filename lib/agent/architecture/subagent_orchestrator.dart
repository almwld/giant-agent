import 'dart:async';

class SubagentTask {
  const SubagentTask({required this.id, required this.title, required this.prompt, this.dependsOn = const <String>[]});
  final String id;
  final String title;
  final String prompt;
  final List<String> dependsOn;
}

class SubagentResult {
  const SubagentResult({required this.taskId, required this.status, this.output, this.error});
  final String taskId;
  final String status;
  final String? output;
  final String? error;
}

typedef SubagentExecutor = Future<String> Function(SubagentTask task);
typedef SubagentEventSink = FutureOr<void> Function(Map<String, Object?> event);

/// Bounded dependency-aware worker pool. It reuses the caller's executor and
/// never creates another model, terminal, or tool runtime.
class SubagentOrchestrator {
  SubagentOrchestrator({required SubagentExecutor execute, required SubagentEventSink onEvent, this.maxConcurrency = 3})
      : _execute = execute, _onEvent = onEvent {
    if (maxConcurrency < 1 || maxConcurrency > 8) {
      throw ArgumentError.value(maxConcurrency, 'maxConcurrency', 'Concurrency must be between 1 and 8.');
    }
  }

  final SubagentExecutor _execute;
  final SubagentEventSink _onEvent;
  final int maxConcurrency;
  bool _cancelRequested = false;

  void cancel() => _cancelRequested = true;

  Future<List<SubagentResult>> run(List<SubagentTask> tasks) async {
    _cancelRequested = false;
    _validate(tasks);
    final byId = {for (final task in tasks) task.id: task};
    final pending = tasks.map((task) => task.id).toSet();
    final results = <String, SubagentResult>{};
    final active = <String, Future<void>>{};

    Future<void> start(SubagentTask task) async {
      await _emit(task, 'subagent_started', 'running');
      try {
        final output = await _execute(task);
        results[task.id] = SubagentResult(taskId: task.id, status: 'completed', output: output);
        await _emit(task, 'subagent_completed', 'completed', details: 'اكتمل الوكيل الفرعي وأُرفقت نتيجته.');
      } catch (error) {
        results[task.id] = SubagentResult(taskId: task.id, status: 'failed', error: error.toString());
        await _emit(task, 'subagent_failed', 'failed', details: error.toString());
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
          final dependencyResults = task.dependsOn.map((id) => results[id]).toList();
          if (dependencyResults.any((r) => r != null && r.status != 'completed')) {
            pending.remove(task.id);
            results[task.id] = SubagentResult(taskId: task.id, status: 'skipped');
            await _emit(task, 'subagent_skipped', 'interrupted', details: 'تعذر التنفيذ بسبب فشل إحدى التبعيات.');
            scheduled = true;
            continue;
          }
          if (dependencyResults.any((r) => r == null)) continue;
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

  Future<void> _emit(SubagentTask task, String type, String status, {String? details}) async {
    await _onEvent(<String, Object?>{
      'id': 'subagent_${task.id}_${type}_${DateTime.now().microsecondsSinceEpoch}',
      'type': type,
      'task_id': task.id,
      'title': task.title,
      'status': status,
      if (details != null) 'details': details,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });
  }

  void _validate(List<SubagentTask> tasks) {
    final ids = <String>{};
    for (final task in tasks) {
      if (task.id.trim().isEmpty || task.prompt.trim().isEmpty) {
        throw ArgumentError('Subagent ids and prompts must not be empty.');
      }
      if (!ids.add(task.id)) throw ArgumentError('Duplicate subagent id: ${task.id}');
    }
    for (final task in tasks) {
      for (final dependency in task.dependsOn) {
        if (!ids.contains(dependency)) throw ArgumentError('Unknown dependency $dependency for subagent ${task.id}.');
        if (dependency == task.id) throw ArgumentError('A subagent cannot depend on itself.');
      }
    }
    final visited = <String>{};
    final visiting = <String>{};
    void visit(String id) {
      if (visiting.contains(id)) throw ArgumentError('Subagent dependency cycle includes $id.');
      if (visited.contains(id)) return;
      visiting.add(id);
      for (final dependency in tasks.firstWhere((task) => task.id == id).dependsOn) {
        visit(dependency);
      }
      visiting.remove(id);
      visited.add(id);
    }
    for (final task in tasks) { visit(task.id); }
  }
}
