import '../models/task_model.dart';
import '../services/task_store.dart';

typedef TaskPlanner = Future<List<TaskStep>> Function(String description);
typedef TaskStepExecutor = Future<TaskExecutionResult> Function(
  TaskModel task,
  TaskStep step,
);
typedef TaskStepVerifier = Future<TaskVerificationResult> Function(
  TaskModel task,
  TaskStep step,
  TaskExecutionResult result,
);
typedef TaskVerifier = Future<TaskVerificationResult> Function(TaskModel task);

class TaskExecutionResult {
  const TaskExecutionResult({
    required this.ok,
    this.output = const {},
    this.error,
  });

  final bool ok;
  final Map<String, dynamic> output;
  final String? error;
}

class TaskVerificationResult {
  const TaskVerificationResult({
    required this.verified,
    this.evidence = '',
    this.reason,
  });

  final bool verified;
  final String evidence;
  final String? reason;
}

/// Checkpointed orchestration core. It fails closed until real planner,
/// executor, and independent verification callbacks are configured.
/// Interrupted side effects are never replayed automatically.
class TaskManager {
  static final TaskManager _instance = TaskManager._internal();

  factory TaskManager() => _instance;

  TaskManager._internal() : _store = SqliteTaskStore();

  TaskManager.forTesting({
    TaskPlanner? planner,
    TaskStepExecutor? executor,
    TaskStepVerifier? stepVerifier,
    TaskVerifier? verifier,
    TaskStore? store,
  })  : _planner = planner,
        _executor = executor,
        _stepVerifier = stepVerifier,
        _verifier = verifier,
        _store = store;

  TaskPlanner? _planner;
  TaskStepExecutor? _executor;
  TaskStepVerifier? _stepVerifier;
  TaskVerifier? _verifier;
  TaskStore? _store;
  final List<TaskModel> _tasks = [];
  final Set<String> _runningTaskIds = {};
  String _currentTaskId = '';
  bool _initialized = false;
  Future<void>? _initializing;

  void configureRuntime({
    required TaskPlanner planner,
    required TaskStepExecutor executor,
    required TaskStepVerifier stepVerifier,
    required TaskVerifier verifier,
    TaskStore? store,
  }) {
    if (_runningTaskIds.isNotEmpty || _tasks.isNotEmpty) {
      throw StateError('Configure the runtime before creating or executing tasks.');
    }
    _planner = planner;
    _executor = executor;
    _stepVerifier = stepVerifier;
    _verifier = verifier;
    if (store != null) {
      _store = store;
      _initialized = false;
    }
  }

  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    return _initializing ??= _loadAndRecover().whenComplete(() {
      _initializing = null;
    });
  }

  Future<void> _loadAndRecover() async {
    final store = _store;
    if (store != null) {
      await store.initialize();
      final storedTasks = await store.loadAll();
      for (final task in storedTasks) {
        final interruptedSteps = task.steps.where((step) =>
            step.status == TaskStepStatus.inProgress ||
            step.status == TaskStepStatus.verifying).toList();
        final taskNeedsInterruption = interruptedSteps.isNotEmpty ||
            task.status == TaskStatus.planning ||
            task.status == TaskStatus.verifying;
        if (taskNeedsInterruption) {
          for (final step in interruptedSteps) {
            step
              ..status = TaskStepStatus.interrupted
              ..error = 'Process ended while this step was active; it was not replayed.'
              ..finishedAt = DateTime.now();
          }
          task
            ..status = TaskStatus.interrupted
            ..error = 'Task was interrupted; review side effects before creating a new attempt.';
          await store.save(task);
        } else if (task.status == TaskStatus.inProgress) {
          // The previous operation reached a durable between-step checkpoint.
          // Continue only at the next pending step; never replay a running step.
          task
            ..status = TaskStatus.pending
            ..error = null;
          await store.save(task);
        }
        _tasks.add(task);
      }
    }
    if (_currentTaskId.isEmpty && _tasks.isNotEmpty) {
      _currentTaskId = _tasks.first.id;
    }
    _initialized = true;
  }

  Future<void> _persist(TaskModel task) async {
    await _store?.save(task);
  }

  Future<TaskModel> createTask(
    String description, {
    TaskPriority priority = TaskPriority.medium,
  }) async {
    final text = description.trim();
    final task = TaskModel(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: _taskTitle(text),
      description: text,
      priority: priority,
      status: TaskStatus.planning,
      createdAt: DateTime.now(),
    );

    try {
      await initialize();
    } catch (error) {
      task
        ..status = TaskStatus.blocked
        ..error = 'Task storage could not be initialized: $error';
      return task;
    }
    _tasks.add(task);
    _currentTaskId = task.id;
    try {
      await _persist(task);
    } catch (error) {
      task
        ..status = TaskStatus.blocked
        ..error = 'Task checkpoint could not be saved: $error';
      return task;
    }

    if (text.isEmpty) {
      task
        ..status = TaskStatus.failed
        ..error = 'Task description cannot be empty.';
      await _persist(task);
      return task;
    }
    final planner = _planner;
    if (planner == null) {
      task
        ..status = TaskStatus.blocked
        ..error = 'No real planner is configured; no plan was fabricated.';
      await _persist(task);
      return task;
    }

    try {
      final plan = await planner(text);
      _validatePlan(plan);
      task.steps.addAll(plan);
      task.status = TaskStatus.pending;
      await _persist(task);
    } catch (error) {
      task
        ..status = TaskStatus.failed
        ..error = 'Planning failed: $error';
      try {
        await _persist(task);
      } catch (storageError) {
        task.error = '${task.error} Checkpoint failure: $storageError';
      }
    }
    return task;
  }

  Future<Map<String, dynamic>> executeNextStep(String taskId) async {
    try {
      await initialize();
    } catch (error) {
      return _failure('Task storage could not be initialized: $error', status: 'storage_error');
    }
    final task = _findTask(taskId);
    if (task == null) return _failure('Task not found.', status: 'not_found');
    if (task.status == TaskStatus.completed) {
      return {'ok': true, 'status': task.status.name, 'message': 'Task already completed.'};
    }
    if (task.status == TaskStatus.failed ||
        task.status == TaskStatus.blocked ||
        task.status == TaskStatus.interrupted ||
        task.status == TaskStatus.cancelled) {
      return _failure(task.error ?? 'Task is not executable.', status: task.status.name);
    }
    if (!_runningTaskIds.add(taskId)) {
      return _failure('Another step for this task is already running.', status: 'in_progress');
    }

    try {
      final executor = _executor;
      final stepVerifier = _stepVerifier;
      final verifier = _verifier;
      if (executor == null || stepVerifier == null || verifier == null) {
        task
          ..status = TaskStatus.blocked
          ..error = 'Execution is blocked until real execution and verification adapters are configured.';
        await _persist(task);
        return _failure(task.error!, status: task.status.name);
      }

      final pending = task.steps.where((step) => step.status == TaskStepStatus.pending).toList();
      if (pending.isEmpty) {
        if (task.steps.any((step) => step.status != TaskStepStatus.completed)) {
          task
            ..status = TaskStatus.blocked
            ..error = 'No runnable step remains; unresolved dependencies prevent completion.';
          await _persist(task);
          return _failure(task.error!, status: task.status.name);
        }
        return await _verifyTask(task, verifier);
      }

      final completedIds = task.steps
          .where((step) => step.status == TaskStepStatus.completed)
          .map((step) => step.id)
          .toSet();
      TaskStep? step;
      for (final candidate in pending) {
        if (candidate.dependencies.every(completedIds.contains)) {
          step = candidate;
          break;
        }
      }
      if (step == null) {
        task
          ..status = TaskStatus.blocked
          ..error = 'No pending step is runnable from the completed dependency set.';
        await _persist(task);
        return _failure(task.error!, status: task.status.name);
      }

      task.status = TaskStatus.inProgress;
      step
        ..status = TaskStepStatus.inProgress
        ..startedAt = DateTime.now()
        ..error = null;
      step.attempts++;
      final stopwatch = Stopwatch()..start();
      try {
        // Persist the in-progress state before invoking a side-effecting tool.
        await _persist(task);
        final result = await executor(task, step);
        if (!result.ok) throw StateError(result.error ?? 'Executor reported failure.');
        step
          ..status = TaskStepStatus.verifying
          ..output = result.output;
        await _persist(task);
        final verification = await stepVerifier(task, step, result);
        if (!verification.verified || verification.evidence.trim().isEmpty) {
          throw StateError(verification.reason ?? 'Step verification returned no positive evidence.');
        }
        step
          ..status = TaskStepStatus.completed
          ..evidence = verification.evidence;
        await _persist(task);
      } catch (error) {
        step
          ..status = TaskStepStatus.failed
          ..error = error.toString();
        task
          ..status = TaskStatus.failed
          ..error = 'Step ${step.id} failed: $error';
        try {
          await _persist(task);
        } catch (storageError) {
          task.error = '${task.error} Checkpoint failure: $storageError';
        }
        return _failure(task.error!, status: task.status.name, stepId: step.id);
      } finally {
        stopwatch.stop();
        step
          ..finishedAt = DateTime.now()
          ..durationMs = stopwatch.elapsedMilliseconds;
        try {
          await _persist(task);
        } catch (_) {
          // The last durable checkpoint remains in-progress and will recover as
          // interrupted on the next process start; it is never replayed silently.
        }
      }

      if (task.steps.every((item) => item.status == TaskStepStatus.completed)) {
        return await _verifyTask(task, verifier, lastStepId: step.id);
      }
      return {
        'ok': true,
        'status': task.status.name,
        'step_id': step.id,
        'step_status': step.status.name,
        'remaining': task.steps.where((item) => item.status == TaskStepStatus.pending).length,
        'evidence': step.evidence,
      };
    } finally {
      _runningTaskIds.remove(taskId);
    }
  }

  Future<Map<String, dynamic>> _verifyTask(
    TaskModel task,
    TaskVerifier verifier, {
    String? lastStepId,
  }) async {
    task.status = TaskStatus.verifying;
    try {
      await _persist(task);
      final result = await verifier(task);
      if (!result.verified || result.evidence.trim().isEmpty) {
        throw StateError(result.reason ?? 'Task verification returned no positive evidence.');
      }
      task
        ..status = TaskStatus.completed
        ..completedAt = DateTime.now()
        ..verificationEvidence = result.evidence
        ..error = null;
      await _persist(task);
      return {
        'ok': true,
        'status': task.status.name,
        'step_id': lastStepId,
        'verification_evidence': result.evidence,
        'task': task.toJson(),
      };
    } catch (error) {
      task
        ..status = TaskStatus.failed
        ..error = 'Final verification failed: $error';
      try {
        await _persist(task);
      } catch (storageError) {
        task.error = '${task.error} Checkpoint failure: $storageError';
      }
      return _failure(task.error!, status: task.status.name, stepId: lastStepId);
    }
  }

  void _validatePlan(List<TaskStep> steps) {
    if (steps.isEmpty) throw const FormatException('Planner returned an empty plan.');
    final ids = steps.map((step) => step.id).toList();
    if (ids.any((id) => id.trim().isEmpty) || ids.toSet().length != ids.length) {
      throw const FormatException('Plan step IDs must be non-empty and unique.');
    }
    final knownIds = ids.toSet();
    for (final step in steps) {
      if (step.action.trim().isEmpty || step.type.trim().isEmpty) {
        throw FormatException('Step ${step.id} must have an action and type.');
      }
      if (step.dependencies.any((dependency) => !knownIds.contains(dependency) || dependency == step.id)) {
        throw FormatException('Step ${step.id} has an unknown or self dependency.');
      }
    }

    final remaining = steps.map((step) => step.id).toSet();
    final resolved = <String>{};
    while (remaining.isNotEmpty) {
      final ready = steps
          .where((step) => remaining.contains(step.id) && step.dependencies.every(resolved.contains))
          .map((step) => step.id)
          .toList();
      if (ready.isEmpty) throw const FormatException('Plan contains a dependency cycle.');
      resolved.addAll(ready);
      remaining.removeAll(ready);
    }
  }

  TaskModel? _findTask(String id) {
    for (final task in _tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  Map<String, dynamic> _failure(String message, {required String status, String? stepId}) => {
        'ok': false,
        'status': status,
        'step_id': stepId,
        'error': message,
      };

  String _taskTitle(String description) =>
      description.length > 48 ? '${description.substring(0, 48)}…' : description;

  String get currentTaskId => _currentTaskId;

  String getProgress(String taskId) {
    final task = _findTask(taskId);
    if (task == null) return 'لا توجد مهمة';
    final total = task.steps.length;
    if (total == 0) return '0/0 (${task.status.name})';
    final completed = task.steps.where((step) => step.status == TaskStepStatus.completed).length;
    return '$completed/$total (${(completed / total * 100).toStringAsFixed(0)}%)';
  }

  List<TaskModel> getTasks() => List.unmodifiable(_tasks);

  Future<void> clearTasks() async {
    if (_runningTaskIds.isNotEmpty) {
      throw StateError('Cannot clear tasks while execution is in progress.');
    }
    await initialize();
    await _store?.clear();
    _tasks.clear();
    _currentTaskId = '';
  }
}
