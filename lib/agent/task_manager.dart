import 'dart:convert';

import '../services/agent_service.dart';
import '../domain/kernel/agent_kernel_store.dart';
import '../domain/kernel/task_recovery_engine.dart';

/// Persistent task lifecycle backed by the real local agent runtime.
/// Task history survives process restarts; completion is recorded only after
/// the agent returns its final result.
enum TaskExecutionOutcome {
  completed,
  interrupted,
  failed,
}

class TaskManager {
  TaskManager._internal({AgentKernelStore? store})
      : _store = store ?? AgentKernelStore(),
        _agent = AgentService.instance;

  TaskManager.withStore(AgentKernelStore store)
      : _store = store,
        _agent = AgentService.instance;

  static final TaskManager _instance = TaskManager._internal();
  factory TaskManager() => _instance;

  final AgentKernelStore _store;
  final AgentService _agent;
  final List<Map<String, dynamic>> _tasks = [];
  String _currentTask = '';
  bool _executing = false;
  Future<void>? _loading;

  /// Loads and reconciles the durable task snapshot during app startup.
  Future<void> initialize() => _ensureLoaded();

  Future<void> _ensureLoaded() {
    _loading ??= _load();
    return _loading!;
  }

  Future<void> _load() async {
    // Compatibility import is isolated in the data layer. TaskManager itself
    // never reads or writes SharedPreferences.
    await _store.migrateLegacyTaskSnapshot();
    await RecoveryEngine(_store).recoverInterruptedTasks();
    final persisted = await _store.getTasks();
    _tasks
      ..clear()
      ..addAll(persisted.map(_normalizeRecoveredTask));
    if (_tasks.isNotEmpty) {
      _currentTask = _tasks.last['id']?.toString() ?? '';
    }
    if (_tasks.any((task) => task['status'] == 'paused')) {
      await _persist();
    }
  }

  Map<String, dynamic> _normalizeRecoveredTask(
    Map<String, dynamic> source,
  ) {
    final task = Map<String, dynamic>.from(source);
    // A process may die while a task is running. Never report it as actively
    // executing after restart; ambiguous work remains paused for reconciliation.
    if (task['status'] == 'running') {
      task['status'] = 'paused';
      task['recovery_note'] =
          'توقف التطبيق أثناء التنفيذ؛ راجع الحالة قبل استئناف المهمة.';
      final steps = task['steps'];
      if (steps is List) {
        for (final rawStep in steps) {
          if (rawStep is Map && rawStep['status'] == 'running') {
            rawStep['status'] = 'pending';
          }
        }
      }
    }
    return task;
  }

  Future<void> _persist() async {
    // Task snapshots are updated in-place, but each SQLite upsert is atomic.
    // Do not hide storage errors: callers must know if a state transition
    // was not durably committed.
    for (final task in _tasks) {
      await _store.saveTask(task);
    }
  }

  Map<String, dynamic> _copyTask(Map<String, dynamic> task) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(task)) as Map);

  Future<Map<String, dynamic>> createTask(
    String description, {
    String conversationId = 'global',
  }) async {
    await _ensureLoaded();
    final goal = description.trim();
    if (goal.isEmpty) throw ArgumentError.value(description, 'description');
    final now = DateTime.now();
    final id = '${now.microsecondsSinceEpoch}_${_tasks.length + 1}';
    final task = <String, dynamic>{
      'id': id,
      'description': goal,
      'conversation_id': conversationId,
      'status': 'pending',
      'steps': <Map<String, dynamic>>[
        {
          'step': 1,
          'action': 'تنفيذ المهمة بواسطة محرك الوكيل المحلي',
          'type': 'agent_execution',
          'status': 'pending',
        }
      ],
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };
    _tasks.add(task);
    _currentTask = id;
    await _store.saveTaskWithEvents(task, events: [
      {
        'type': 'task_created',
        'status': 'pending',
        'payload': <String, Object?>{
          'conversation_id': conversationId,
          'description': goal,
        },
      },
    ]);
    return _copyTask(task);
  }

  Map<String, dynamic>? _findTask(String taskId) {
    for (final task in _tasks) {
      if (task['id'] == taskId) return task;
    }
    return null;
  }

  Map<String, dynamic> _firstStep(Map<String, dynamic> task) {
    final steps = task['steps'];
    if (steps is! List || steps.isEmpty || steps.first is! Map) {
      throw StateError('سجل المهمة لا يحتوي على خطوة قابلة للتنفيذ.');
    }
    return Map<String, dynamic>.from(steps.first as Map);
  }

  /// Marks a task as running when execution is owned by ChatScreen/AgentKernel.
  /// This keeps the persisted task lifecycle in sync without executing it twice.
  Future<void> markRunning(String taskId, {String? requestId}) async {
    await _ensureLoaded();
    if (_executing && _currentTask != taskId) {
      throw StateError('يوجد تنفيذ مهمة جارٍ بالفعل.');
    }
    final task = _findTask(taskId);
    if (task == null) throw StateError('المهمة غير موجودة.');
    if (task['status'] == 'completed' || task['status'] == 'cancelled') {
      throw StateError('لا يمكن تشغيل مهمة منتهية.');
    }
    _currentTask = taskId;
    _executing = true;
    final step = _firstStep(task);
    step['status'] = 'running';
    (task['steps'] as List)[0] = step;
    task['status'] = 'running';
    task['started_at'] ??= DateTime.now().toIso8601String();
    task['updated_at'] = DateTime.now().toIso8601String();
    task.remove('error');
    task.remove('recovery_note');
    if (requestId != null && requestId.isNotEmpty) {
      task['request_id'] = requestId;
    }
    await _store.saveTaskWithEvents(task, events: [
      {
        'type': 'task_started',
        'status': 'running',
        'payload': <String, Object?>{
          if (requestId != null && requestId.isNotEmpty) 'request_id': requestId,
        },
      },
      {
        'type': 'step_started',
        'status': 'running',
        'payload': <String, Object?>{
          'step': step['step'],
          'action': step['action'],
        },
      },
    ]);
  }

  Future<void> markCompleted(String taskId, String result) async {
    await _ensureLoaded();
    final task = _findTask(taskId);
    if (task == null) return;
    final step = _firstStep(task);
    step['status'] = 'completed';
    step['result'] = result;
    (task['steps'] as List)[0] = step;
    task['status'] = 'completed';
    task['result'] = result;
    task['completed_at'] = DateTime.now().toIso8601String();
    task['updated_at'] = task['completed_at'];
    task.remove('error');
    if (_currentTask == taskId) _executing = false;
    await _store.saveTaskWithEvents(task, events: [
      {
        'type': 'step_completed',
        'status': 'completed',
        'payload': <String, Object?>{'step': step['step'], 'result': result},
      },
      {
        'type': 'task_completed',
        'status': 'completed',
        'payload': <String, Object?>{'result': result},
      },
    ]);
  }

  Future<void> markFailed(String taskId, String error) async {
    await _ensureLoaded();
    final task = _findTask(taskId);
    if (task == null) return;
    final step = _firstStep(task);
    step['status'] = 'failed';
    step['error'] = error;
    (task['steps'] as List)[0] = step;
    task['status'] = 'failed';
    task['error'] = error;
    task['updated_at'] = DateTime.now().toIso8601String();
    if (_currentTask == taskId) _executing = false;
    await _store.saveTaskWithEvents(task, events: [
      {
        'type': 'step_failed',
        'status': 'failed',
        'payload': <String, Object?>{'step': step['step'], 'error': error},
      },
      {
        'type': 'task_failed',
        'status': 'failed',
        'payload': <String, Object?>{'error': error},
      },
    ]);
  }

  Future<void> markInterrupted(String taskId, String note) async {
    await _ensureLoaded();
    final task = _findTask(taskId);
    if (task == null) return;
    final step = _firstStep(task);
    step['status'] = 'uncertain';
    step['recovery_state'] = 'side_effect_unknown';
    (task['steps'] as List)[0] = step;
    task['status'] = 'paused';
    task['recovery_note'] = note;
    task['updated_at'] = DateTime.now().toIso8601String();
    if (_currentTask == taskId) _executing = false;
    await _store.saveTaskWithEvents(task, events: [
      {
        'type': 'step_interrupted',
        'status': 'uncertain',
        'payload': <String, Object?>{'step': step['step'], 'note': note},
      },
      {
        'type': 'task_paused',
        'status': 'paused',
        'payload': <String, Object?>{'reason': note},
      },
    ]);
  }

  Future<void> markCancelled(String taskId) async {
    await _ensureLoaded();
    final task = _findTask(taskId);
    if (task == null) return;
    final step = _firstStep(task);
    step['status'] = 'cancelled';
    (task['steps'] as List)[0] = step;
    task['status'] = 'cancelled';
    task['updated_at'] = DateTime.now().toIso8601String();
    if (_currentTask == taskId) _executing = false;
    await _store.saveTaskWithEvents(task, events: [
      {
        'type': 'task_cancelled',
        'status': 'cancelled',
        'payload': <String, Object?>{'step': step['step']},
      },
    ]);
  }

  Future<bool> selectTask(String taskId) async {
    await _ensureLoaded();
    final exists = _tasks.any((item) => item['id'] == taskId);
    if (!exists || _executing) return false;
    _currentTask = taskId;
    await _persist();
    return true;
  }

  Future<Map<String, dynamic>> resumeTask(String taskId) async {
    await _ensureLoaded();
    if (_executing) throw StateError('يوجد تنفيذ مهمة جارٍ بالفعل.');
    final task = _tasks.cast<Map<String, dynamic>>().firstWhere(
      (item) => item['id'] == taskId,
      orElse: () => <String, dynamic>{},
    );
    if (task.isEmpty) return {'status': 'missing', 'message': 'المهمة غير موجودة.'};
    if (task['status'] == 'completed') {
      return {'status': 'completed', 'task_summary': _copyTask(task)};
    }
    if (task['status'] != 'paused' && task['status'] != 'failed' && task['status'] != 'pending') {
      return {'status': task['status'], 'task_summary': _copyTask(task)};
    }
    _currentTask = taskId;
    final step = _firstStep(task);
    final checkpoint = (step['result'] ??
            step['checkpoint_note'] ??
            task['recovery_note'] ??
            '')
        .toString()
        .trim();
    if (checkpoint.isNotEmpty) task['resume_context'] = checkpoint;
    task['status'] = 'pending';
    task.remove('error');
    task.remove('recovery_note');
    task['updated_at'] = DateTime.now().toIso8601String();
    await _store.saveTaskWithEvents(task, events: [
      {
        'type': 'task_resume_requested',
        'status': 'pending',
        'payload': <String, Object?>{
          'policy': 'explicit_user_action',
          'previous_step_state': step['status'],
        },
      },
    ]);
    return executeNextStep();
  }

  static TaskExecutionOutcome classifyResult(String output) {
    if (output.startsWith('تم إيقاف') ||
        output.startsWith('وصل الوكيل إلى الحد الآمن') ||
        output.startsWith('أوقف الوكيل تكرار استدعاء الأداة') ||
        output.contains('[تم إيقاف التوليد]')) {
      return TaskExecutionOutcome.interrupted;
    }
    if (output.isEmpty ||
        output.startsWith('ERROR:') ||
        output.startsWith('تعذر تشغيل النموذج المحلي:') ||
        output.startsWith('تعذر تحليل استدعاء الأداة أو تنفيذه:') ||
        output.startsWith('تعذر إكمال الطلب:') ||
        output.startsWith('⚠️ اختر نموذج') ||
        output.startsWith('⚠️ استورد نموذج')) {
      return TaskExecutionOutcome.failed;
    }
    return TaskExecutionOutcome.completed;
  }

  Future<Map<String, dynamic>> executeNextStep() async {
    await _ensureLoaded();
    if (_executing) throw StateError('يوجد تنفيذ مهمة جارٍ بالفعل.');
    final task = _tasks.cast<Map<String, dynamic>>().firstWhere(
      (item) => item['id'] == _currentTask,
      orElse: () => <String, dynamic>{},
    );
    if (task.isEmpty) return {'status': 'missing', 'message': 'لا توجد مهمة نشطة.'};
    if (task['status'] == 'completed') {
      return {'status': 'completed', 'task_summary': _copyTask(task)};
    }

    _executing = true;
    final step = (task['steps'] as List).first as Map<String, dynamic>;
    task['status'] = 'running';
    task['started_at'] ??= DateTime.now().toIso8601String();
    task['updated_at'] = DateTime.now().toIso8601String();
    step['status'] = 'running';
    try {
      await _store.saveTaskWithEvents(task, events: [
        {
          'type': 'task_started',
          'status': 'running',
          'payload': <String, Object?>{'execution_path': 'task_manager'},
        },
        {
          'type': 'step_started',
          'status': 'running',
          'payload': <String, Object?>{
            'step': step['step'],
            'action': step['action'],
          },
        },
      ]);
      final originalPrompt = task['description'] as String;
      final checkpoint = task['resume_context']?.toString().trim() ?? '';
      final executionPrompt = checkpoint.isEmpty
          ? originalPrompt
          : '''
المهمة الأصلية:
$originalPrompt

نقطة الاستعادة المحفوظة:
$checkpoint

تابع من حالة العمل الحالية. لا تكرر العمليات التي تظهر نتائجها مكتملة؛ افحص الحالة أولاً، ثم نفّذ ما تبقى فقط. لا تعلن اكتمال المهمة قبل التحقق من النتيجة.
''';
      final result = await _agent.runTask(
        executionPrompt,
        conversationId: task['conversation_id']?.toString() ?? 'global',
      );
      final outcome = classifyResult(result);
      if (outcome == TaskExecutionOutcome.interrupted) {
        step['status'] = 'uncertain';
        step['recovery_state'] = 'side_effect_unknown';
        step['result'] = result;
        task['resume_context'] = result;
        task['status'] = 'paused';
        task['recovery_note'] = 'توقف التنفيذ قبل اكتمال المهمة؛ افحص التأثيرات قبل الاستئناف.';
        task['updated_at'] = DateTime.now().toIso8601String();
        await _store.saveTaskWithEvents(task, events: [
          {
            'type': 'step_interrupted',
            'status': 'uncertain',
            'payload': <String, Object?>{'step': step['step'], 'result': result},
          },
          {
            'type': 'task_paused',
            'status': 'paused',
            'payload': <String, Object?>{'reason': task['recovery_note']},
          },
        ]);
        return {
          'status': 'paused',
          'step': step['step'],
          'action': step['action'],
          'result': result,
          'remaining': 1,
          'task_summary': _copyTask(task),
        };
      }
      if (outcome == TaskExecutionOutcome.failed) {
        step['status'] = 'failed';
        step['error'] = result;
        task['status'] = 'failed';
        task['error'] = result;
        task['updated_at'] = DateTime.now().toIso8601String();
        await _store.saveTaskWithEvents(task, events: [
          {
            'type': 'step_failed',
            'status': 'failed',
            'payload': <String, Object?>{'step': step['step'], 'error': result},
          },
          {
            'type': 'task_failed',
            'status': 'failed',
            'payload': <String, Object?>{'error': result},
          },
        ]);
        return {'status': 'failed', 'error': result, 'task_summary': _copyTask(task)};
      }
      step['status'] = 'completed';
      step['result'] = result;
      task['status'] = 'completed';
      task['completed_at'] = DateTime.now().toIso8601String();
      task['updated_at'] = task['completed_at'];
      task['result'] = result;
      task.remove('resume_context');
      task.remove('recovery_note');
      await _store.saveTaskWithEvents(task, events: [
        {
          'type': 'step_completed',
          'status': 'completed',
          'payload': <String, Object?>{'step': step['step'], 'result': result},
        },
        {
          'type': 'task_completed',
          'status': 'completed',
          'payload': <String, Object?>{'result': result},
        },
      ]);
      return {
        'status': 'completed',
        'step': step['step'],
        'action': step['action'],
        'result': result,
        'remaining': 0,
        'task_summary': _copyTask(task),
      };
    } catch (error) {
      step['status'] = 'failed';
      step['error'] = error.toString();
      task['status'] = 'failed';
      task['error'] = error.toString();
      task['updated_at'] = DateTime.now().toIso8601String();
      await _store.saveTaskWithEvents(task, events: [
        {
          'type': 'step_failed',
          'status': 'failed',
          'payload': <String, Object?>{'step': step['step'], 'error': error.toString()},
        },
        {
          'type': 'task_failed',
          'status': 'failed',
          'payload': <String, Object?>{'error': error.toString()},
        },
      ]);
      return {'status': 'failed', 'error': error.toString(), 'task_summary': _copyTask(task)};
    } finally {
      _executing = false;
    }
  }

  Future<bool> cancelTask() async {
    if (!_executing) return false;
    final accepted = await _agent.cancel();
    if (accepted) {
      final task = _tasks.cast<Map<String, dynamic>>().firstWhere(
        (item) => item['id'] == _currentTask,
        orElse: () => <String, dynamic>{},
      );
      if (task.isNotEmpty) {
        task['cancel_requested_at'] = DateTime.now().toIso8601String();
        task['updated_at'] = task['cancel_requested_at'];
        await _persist();
      }
    }
    return accepted;
  }

  String getProgress() {
    final task = _tasks.cast<Map<String, dynamic>>().firstWhere(
      (item) => item['id'] == _currentTask,
      orElse: () => <String, dynamic>{},
    );
    if (task.isEmpty) return 'لا توجد مهمة نشطة';
    final status = task['status'];
    return status == 'completed'
        ? 'مكتمل'
        : status == 'failed'
            ? 'فشل'
            : status == 'paused'
                ? 'متوقف مؤقتاً — قابل للاستئناف'
                : status == 'running'
                    ? 'قيد التنفيذ'
                    : 'بانتظار التنفيذ';
  }

  List<Map<String, dynamic>> getTasks() =>
      _tasks.map(_copyTask).toList(growable: false);

  /// Replays the immutable lifecycle journal for a task in insertion order.
  Future<List<KernelEventRecord>> eventsForTask(String taskId) =>
      _store.taskEvents(taskId);

  Future<List<Map<String, dynamic>>> getTasksForConversation(
    String conversationId, {
    String? status,
  }) async {
    await _ensureLoaded();
    return _tasks
        .where((task) =>
            task['conversation_id']?.toString() == conversationId &&
            (status == null || task['status'] == status))
        .map(_copyTask)
        .toList(growable: false);
  }

  Future<void> clearTasks() async {
    await _ensureLoaded();
    if (_executing) throw StateError('لا يمكن مسح المهام أثناء التنفيذ.');
    _tasks.clear();
    _currentTask = '';
    await _store.clearTasks();
  }

  /// Closes an injected store in tests; the process singleton remains open.
  Future<void> closeForTesting() => _store.close();
}
