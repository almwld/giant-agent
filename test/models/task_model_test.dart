import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/models/task_model.dart';

void main() {
  test('round-trips task, dependency, output, and verification evidence', () {
    final task = TaskModel(
      id: 'task-1',
      title: 'Create artifact',
      description: 'Create and inspect a file',
      priority: TaskPriority.high,
      status: TaskStatus.completed,
      createdAt: DateTime.utc(2026, 1, 2, 3, 4),
      completedAt: DateTime.utc(2026, 1, 2, 3, 5),
      verificationEvidence: 'File exists and is readable.',
      steps: [
        TaskStep(
          id: 'step-1',
          action: 'Write file',
          type: 'file',
          status: TaskStepStatus.completed,
          attempts: 1,
          output: const {'path': 'output.txt'},
          evidence: 'Read back the created file.',
          durationMs: 12,
        ),
      ],
    );

    final restored = TaskModel.fromJson(task.toJson());

    expect(restored.id, task.id);
    expect(restored.priority, TaskPriority.high);
    expect(restored.status, TaskStatus.completed);
    expect(restored.completedAt, task.completedAt);
    expect(restored.verificationEvidence, task.verificationEvidence);
    expect(restored.steps.single.status, TaskStepStatus.completed);
    expect(restored.steps.single.output, {'path': 'output.txt'});
    expect(restored.steps.single.evidence, 'Read back the created file.');
  });

  test('uses safe defaults for absent or unknown fields', () {
    final task = TaskModel.fromJson({
      'id': 'legacy',
      'title': 'Legacy task',
      'priority': 'unrecognized',
      'status': 'unknown',
      'createdAt': 'not-a-date',
      'steps': [
        {'id': 'old-step', 'status': 'unknown'},
      ],
    });

    expect(task.priority, TaskPriority.medium);
    expect(task.status, TaskStatus.pending);
    expect(task.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
    expect(task.steps.single.status, TaskStepStatus.pending);
    expect(task.steps.single.attempts, 0);
  });
}
