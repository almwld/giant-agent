import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/agent/task_manager.dart';
import 'package:giant_agent_x/models/task_model.dart';

void main() {
  group('TaskManager lifecycle', () {
    test('completes only after step and task verification provide evidence', () async {
      var executionCount = 0;
      var stepVerificationCount = 0;
      var taskVerificationCount = 0;
      final manager = TaskManager.forTesting(
        planner: (_) async => [
          TaskStep(id: 'write', action: 'Create artifact', type: 'file'),
          TaskStep(
            id: 'inspect',
            action: 'Inspect artifact',
            type: 'verify',
            dependencies: const ['write'],
          ),
        ],
        executor: (_, step) async {
          executionCount++;
          return TaskExecutionResult(ok: true, output: {'step': step.id});
        },
        stepVerifier: (_, step, result) async {
          stepVerificationCount++;
          expect(result.output['step'], step.id);
          return TaskVerificationResult(verified: true, evidence: 'checked:${step.id}');
        },
        verifier: (task) async {
          taskVerificationCount++;
          expect(task.steps.every((step) => step.status == TaskStepStatus.completed), isTrue);
          return const TaskVerificationResult(
            verified: true,
            evidence: 'Both planned steps completed and verified.',
          );
        },
      );

      final task = await manager.createTask('Create and inspect a file');
      expect(task.status, TaskStatus.pending);
      expect(task.steps, hasLength(2));

      final first = await manager.executeNextStep(task.id);
      expect(first['ok'], isTrue);
      expect(first['step_id'], 'write');
      expect(task.status, TaskStatus.inProgress);

      final second = await manager.executeNextStep(task.id);
      expect(second['ok'], isTrue);
      expect(second['status'], TaskStatus.completed.name);
      expect(task.status, TaskStatus.completed);
      expect(task.verificationEvidence, contains('Both planned steps'));
      expect(executionCount, 2);
      expect(stepVerificationCount, 2);
      expect(taskVerificationCount, 1);
    });

    test('does not report completion after an execution failure', () async {
      var executionCount = 0;
      var taskVerificationCount = 0;
      final manager = TaskManager.forTesting(
        planner: (_) async => [TaskStep(id: 'run', action: 'Run command', type: 'terminal')],
        executor: (_, __) async {
          executionCount++;
          return const TaskExecutionResult(ok: false, error: 'exit code 2');
        },
        stepVerifier: (_, __, ___) async =>
            const TaskVerificationResult(verified: true, evidence: 'must not be reached'),
        verifier: (_) async {
          taskVerificationCount++;
          return const TaskVerificationResult(verified: true, evidence: 'must not be reached');
        },
      );

      final task = await manager.createTask('Run a command');
      final result = await manager.executeNextStep(task.id);

      expect(result['ok'], isFalse);
      expect(result['status'], TaskStatus.failed.name);
      expect(task.steps.single.status, TaskStepStatus.failed);
      expect(task.steps.single.error, contains('exit code 2'));
      expect(task.status, TaskStatus.failed);
      expect(taskVerificationCount, 0);

      final repeated = await manager.executeNextStep(task.id);
      expect(repeated['ok'], isFalse);
      expect(executionCount, 1, reason: 'Failed operations are not replayed automatically.');
    });

    test('blocks execution when no real planner is configured', () async {
      final manager = TaskManager.forTesting();

      final task = await manager.createTask('Do work');

      expect(task.status, TaskStatus.blocked);
      expect(task.steps, isEmpty);
      expect(task.error, contains('No real planner'));
    });

    test('rejects cyclic plans before any execution', () async {
      final manager = TaskManager.forTesting(
        planner: (_) async => [
          TaskStep(id: 'a', action: 'A', type: 'test', dependencies: const ['b']),
          TaskStep(id: 'b', action: 'B', type: 'test', dependencies: const ['a']),
        ],
        executor: (_, __) async => const TaskExecutionResult(ok: true),
        stepVerifier: (_, __, ___) async =>
            const TaskVerificationResult(verified: true, evidence: 'verified'),
        verifier: (_) async =>
            const TaskVerificationResult(verified: true, evidence: 'verified'),
      );

      final task = await manager.createTask('Cyclic plan');

      expect(task.status, TaskStatus.failed);
      expect(task.error, contains('dependency cycle'));
      expect(task.steps, isEmpty);
    });
  });
}
