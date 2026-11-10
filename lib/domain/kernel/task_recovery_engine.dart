import 'package:flutter/foundation.dart';

import 'agent_kernel_store.dart';

/// Reconciles task snapshots against the durable event journal after restart.
///
/// A RUNNING step is ambiguous: its side effect may have happened immediately
/// before process death. It is therefore marked "uncertain", never reset to
/// PENDING and never automatically executed again.
class TaskRecoveryEngine {
  TaskRecoveryEngine(this._store);

  final AgentKernelStore _store;

  Future<List<String>> recoverInterruptedTasks() async {
    final tasks = await _store.getTasks();
    final recovered = <String>[];

    for (final task in tasks) {
      if (task['status'] != 'running') continue;

      final taskId = task['id']?.toString() ?? '';
      if (taskId.isEmpty) continue;

      final steps = task['steps'];
      var uncertainSteps = 0;
      if (steps is List) {
        for (final rawStep in steps) {
          if (rawStep is Map && rawStep['status'] == 'running') {
            rawStep['status'] = 'uncertain';
            rawStep['recovery_state'] = 'side_effect_unknown';
            uncertainSteps++;
          }
        }
      }

      task['status'] = 'paused';
      task['recovery_note'] =
          'انقطع التطبيق أثناء التنفيذ. حالة التأثير الخارجي غير مؤكدة؛ '
          'لن تتم إعادة الخطوة تلقائياً. افحص النتائج قبل الاستئناف.';
      task['recovered_at'] = DateTime.now().toUtc().toIso8601String();
      task['updated_at'] = task['recovered_at'];

      await _store.saveTaskWithEvents(task, events: [
        {
          'type': 'task_interrupted_on_restart',
          'status': 'paused',
          'payload': <String, Object?>{
            'replay': false,
            'uncertain_steps': uncertainSteps,
            'policy': 'manual_reconciliation',
          },
        },
      ]);
      recovered.add(taskId);
    }

    debugPrint(
      'TaskRecoveryEngine: recovered ${recovered.length} interrupted task(s).',
    );
    return recovered;
  }
}
