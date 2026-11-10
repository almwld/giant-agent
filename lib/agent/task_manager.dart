import '../models/task_model.dart';

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

/// In-memory orchestration core. It deliberately fails closed until real
/// planner, executor, and independent verification callbacks are configured.
/// Persistence, retries, and parallel execution are separate follow-up work.
class TaskManager {
  static final TaskManager _instance = TaskManager._internal();

  factory TaskManager() => _instance;

  TaskManager._internal();

  TaskManager.forTesting({
    TaskPlanner? planner,
    TaskStepExecutor? executor,
    TaskStepVerifier? stepVerifier,
    TaskVerifier? verifier,
  })  : _planner = planner,
        _executor = executor,
        _stepVerifier = stepVerifier,
        _verifier = verifier;

  TaskPlanner? _planner;
  TaskStepExecutor? _executor;
  TaskStepVerifier? _stepVerifier;
  TaskVerifier? _verifier;
  final List<TaskModel> _tasks = [];
  final Set<String> _runningTaskIds = {};
  String _currentTaskId = '';

  void configureRuntime({
    required TaskPlanner planner,
    required TaskStepExecutor executor,
    required TaskStepVerifier stepVerifier,
    required TaskVerifier verifier,
  }) {
    if (_runningTaskIds.isNotEmpty) {
      throw StateError('Cannot replace the runtime while a task is executing.');
    }
    _planner = planner;
    _executor = executor;
    _stepVerifier = stepVerifier;
    _verifier = verifier;
  }

  Future<TaskModel> createTask(String description, {TaskPriority priority = TaskPriority.medium}) async {
    final text = description.trim();
    final task = TaskModel(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: _taskTitle(text),
      description: text,
      priority: priority,
      status: TaskStatus.planning,
      createdAt: DateTime.now(),
    );
    _tasks.add(task);
    _currentTaskId = task.id;

    if (text.isEmpty) {
      task.status = TaskStatus.failed;
      task.error = 'Task description cannot be empty.';
      return task;
    }
    final planner = _planner;
    if (planner == null) {
      task.status = TaskStatus.blocked;
      task.error = 'No real planner is configured; no plan was fabricated.';
      return task;
    }

    try {
      final plan = await planner(text);
      _validatePlan(plan);
      task.steps.addAll(plan);
      task.status = TaskStatus.pending;
    } catch (error) {
      task.status = TaskStatus.failed;
      task.error = 'Planning failed: $error';
    }
    return task;
  }

  Future<Map<String, dynamic>> executeNextStep(String taskId) async {
    final task = _findTask(taskId);
    if (task == null) return _failure('Task not found.', status: 'not_found');
    if (task.status == TaskStatus.completed) {
      return {'ok': true, 'status': task.status.name, 'message': 'Task already completed.'};
    }
    if (task.status == TaskStatus.failed || task.status == TaskStatus.blocked || task.status == TaskStatus.cancelled) {
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
        task.status = TaskStatus.blocked;
        task.error = 'Execution is blocked until real execution and verification adapters are configured.';
        return _failure(task.error!, status: task.status.name);
      }

      final pending = task.steps.where((step) => step.status == TaskStepStatus.pending).toList();
      if (pending.isEmpty) {
        if (task.steps.any((step) => step.status != TaskStepStatus.completed)) {
          task.status = TaskStatus.blocked;
          task.error = 'No runnable step remains; unresolved dependencies prevent completion.';
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
        task.status = TaskStatus.blocked;
        task.error = 'No pending step is runnable from the completed dependency set.';
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
        final result = await executor(task, step);
        if (!result.ok) {
          throw StateError(result.error ?? 'Executor reported failure.');
        }
        step
          ..status = TaskStepStatus.verifying
          ..output = result.output;
        final verification = await stepVerifier(task, step, result);
        if (!verification.verified || verification.evidence.trim().isEmpty) {
          throw StateError(verification.reason ?? 'Step verification returned no positive evidence.');
        }
        step
          ..status = TaskStepStatus.completed
          ..evidence = verification.evidence;
      } catch (error) {
        step
          ..status = TaskStepStatus.failed
          ..error = error.toString();
        task
          ..status = TaskStatus.failed
          ..error = 'Step ${step.id} failed: $error';
        return _failure(task.error!, status: task.status.name, stepId: step.id);
      } finally {
        stopwatch.stop();
        step
          ..finishedAt = DateTime.now()
          ..durationMs = stopwatch.elapsedMilliseconds;
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
      final result = await verifier(task);
      if (!result.verified || result.evidence.trim().isEmpty) {
        throw StateError(result.reason ?? 'Task verification returned no positive evidence.');
      }
      task
        ..status = TaskStatus.completed
        ..completedAt = DateTime.now()
        ..verificationEvidence = result.evidence
        ..error = null;
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

  void clearTasks() {
    if (_runningTaskIds.isNotEmpty) {
      throw StateError('Cannot clear tasks while execution is in progress.');
    }
    _tasks.clear();
    _currentTaskId = '';
  }
}
