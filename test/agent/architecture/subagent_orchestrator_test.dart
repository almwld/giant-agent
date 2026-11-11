import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/agent/architecture/subagent_orchestrator.dart';

void main() {
  test('allows a running worker to create and spawn a dynamic child', () async {
    late SubagentOrchestrator orchestrator;
    final executed = <String>[];
    orchestrator = SubagentOrchestrator(
      parentRequestId: 'request-dynamic',
      conversationId: 'chat-dynamic',
      maxConcurrency: 1,
      onEvent: (_) {},
      execute: (task, dependencies, isCancelled) async {
        executed.add(task.id);
        if (task.id == 'planner') {
          await orchestrator.createTask(
            const SubagentTask(id: 'dynamic-review', title: 'Dynamic review',
              prompt: 'Review the implementation', agentType: 'reviewer'),
            creatorTaskId: task.id,
          );
          await orchestrator.spawnTask('dynamic-review');
        }
        return 'result-${task.id}';
      },
    );
    final results = await orchestrator.run([
      const SubagentTask(id: 'planner', title: 'Planner', prompt: 'Plan'),
    ]);
    expect(executed, ['planner', 'dynamic-review']);
    expect(results.map((result) => result.status), ['completed', 'completed']);
    expect(results.last.taskId, 'dynamic-review');
  });

  test('cancels a created child before it is spawned', () async {
    late SubagentOrchestrator orchestrator;
    orchestrator = SubagentOrchestrator(
      parentRequestId: 'request-cancel-created',
      conversationId: 'chat-cancel-created',
      maxConcurrency: 1,
      onEvent: (_) {},
      execute: (task, dependencies, isCancelled) async {
        if (task.id == 'root') {
          await orchestrator.createTask(
            const SubagentTask(id: 'unused', title: 'Unused', prompt: 'Do not run'),
            creatorTaskId: 'root',
          );
          expect(orchestrator.cancelTask('unused'), isTrue);
          expect(orchestrator.status('unused')['status'], 'cancelled');
        }
        return 'done';
      },
    );
    final results = await orchestrator.run([
      const SubagentTask(id: 'root', title: 'Root', prompt: 'Root'),
    ]);
    expect(results.map((result) => result.status), ['completed', 'cancelled']);
  });

  test('delivers messages and records shared goal updates', () async {
    late SubagentOrchestrator orchestrator;
    final received = Completer<Map<String, Object?>?>();
    orchestrator = SubagentOrchestrator(
      parentRequestId: 'request-messages',
      conversationId: 'chat-messages',
      maxConcurrency: 2,
      onEvent: (_) {},
      execute: (task, dependencies, isCancelled) async {
        if (task.id == 'sender') {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await orchestrator.sendMessage(
            fromTaskId: 'sender', toTaskId: 'receiver', content: 'API audit complete',
          );
          await orchestrator.updateGoal(taskId: 'sender', goal: 'Prioritize security fixes');
          return 'sent';
        }
        if (task.id == 'receiver') {
          received.complete(await orchestrator.waitForMessage(
            taskId: 'receiver', timeout: const Duration(seconds: 2),
          ));
          return 'received';
        }
        return 'unexpected';
      },
    );
    await orchestrator.run([
      const SubagentTask(id: 'sender', title: 'Sender', prompt: 'Send result', agentType: 'explore'),
      const SubagentTask(id: 'receiver', title: 'Receiver', prompt: 'Wait for result', agentType: 'reviewer'),
    ]);
    expect((await received.future)?['content'], 'API audit complete');
    expect(orchestrator.currentGoal, 'Prioritize security fixes');
  });

  test('enforces dynamic task count and nesting depth', () async {
    late SubagentOrchestrator orchestrator;
    orchestrator = SubagentOrchestrator(
      parentRequestId: 'request-limits',
      conversationId: 'chat-limits',
      maxConcurrency: 1,
      maxTasks: 2,
      maxDepth: 1,
      onEvent: (_) {},
      execute: (task, dependencies, isCancelled) async {
        if (task.id == 'root') {
          await orchestrator.createTask(
            const SubagentTask(id: 'child', title: 'Child', prompt: 'Child'),
            creatorTaskId: 'root',
          );
          await expectLater(
            orchestrator.createTask(
              const SubagentTask(id: 'overflow', title: 'Overflow', prompt: 'Overflow'),
              creatorTaskId: 'root',
            ),
            throwsStateError,
          );
          await orchestrator.spawnTask('child');
        } else {
          await expectLater(
            orchestrator.createTask(
              const SubagentTask(id: 'grandchild', title: 'Grandchild', prompt: 'Grandchild'),
              creatorTaskId: 'child',
            ),
            throwsStateError,
          );
        }
        return 'ok';
      },
    );
    final results = await orchestrator.run([
      const SubagentTask(id: 'root', title: 'Root', prompt: 'Root'),
    ]);
    expect(results.map((result) => result.status), ['completed', 'completed']);
  });

  test('runs independent agents concurrently and respects dependencies', () async {
    final active = <String>{};
    var peak = 0;
    var dependencyOutput = '';
    final events = <Map<String, Object?>>[];
    final orchestrator = SubagentOrchestrator(
      parentRequestId: 'request-1',
      conversationId: 'chat-1',
      maxConcurrency: 2,
      onEvent: events.add,
      execute: (task, dependencies, isCancelled) async {
        if (task.id == 'synthesis') {
          dependencyOutput = dependencies['research']!.output!;
        }
        active.add(task.id);
        if (active.length > peak) peak = active.length;
        await Future<void>.delayed(const Duration(milliseconds: 15));
        active.remove(task.id);
        return 'result-${task.id}';
      },
    );
    final results = await orchestrator.run([
      const SubagentTask(id: 'research', title: 'Research', prompt: 'Research', agentType: 'explore'),
      const SubagentTask(id: 'audit', title: 'Audit', prompt: 'Audit', agentType: 'reviewer'),
      const SubagentTask(id: 'synthesis', title: 'Synthesis', prompt: 'Synthesize', agentType: 'plan', dependsOn: ['research', 'audit']),
    ]);
    expect(peak, 2);
    expect(results.map((r) => r.status), ['completed', 'completed', 'completed']);
    expect(results.last.output, 'result-synthesis');
    expect(dependencyOutput, 'result-research');
    expect(events.map((e) => e['type']), contains('subagent_completed'));
    expect(events.where((event) => event['type'] == 'subagent_created'), hasLength(3));
    expect(events.take(3).every((event) => event['type'] == 'subagent_created'), isTrue);
    expect(events.every((event) => event['request_id'] == 'request-1'), isTrue);
  });

  test('coder workers hold an exclusive workspace lease', () async {
    final active = <String>{};
    var peak = 0;
    var coderOverlapped = false;
    final orchestrator = SubagentOrchestrator(
      parentRequestId: 'request-coder-lease',
      conversationId: 'chat-coder-lease',
      maxConcurrency: 3,
      onEvent: (_) {},
      execute: (task, dependencies, isCancelled) async {
        active.add(task.id);
        if (active.length > peak) peak = active.length;
        if (active.contains('coder') && active.length > 1) {
          coderOverlapped = true;
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
        active.remove(task.id);
        return 'done';
      },
    );
    final results = await orchestrator.run([
      const SubagentTask(id: 'coder', title: 'Coder', prompt: 'Edit files', agentType: 'coder'),
      const SubagentTask(id: 'explore', title: 'Explore', prompt: 'Inspect files', agentType: 'explore'),
      const SubagentTask(id: 'review', title: 'Review', prompt: 'Review changes', agentType: 'reviewer'),
    ]);
    expect(coderOverlapped, isFalse);
    expect(peak, 2); // Read-only workers may overlap after the coder lease ends.
    expect(results.map((result) => result.status), everyElement('completed'));
  });

  test('can execute a bounded repair batch after an initial batch', () async {
    final executed = <String>[];
    final orchestrator = SubagentOrchestrator(
      parentRequestId: 'request-replan',
      conversationId: 'chat-replan',
      maxConcurrency: 1,
      onEvent: (_) {},
      execute: (task, dependencies, isCancelled) async {
        executed.add(task.id);
        return 'repaired:${task.id}';
      },
    );

    final first = await orchestrator.run([
      const SubagentTask(id: 'initial', title: 'Initial', prompt: 'Initial'),
    ]);
    final repair = await orchestrator.run([
      const SubagentTask(id: 'repair-1', title: 'Repair', prompt: 'Repair'),
    ]);

    expect(first.single.status, 'completed');
    expect(repair.single.output, 'repaired:repair-1');
    expect(executed, ['initial', 'repair-1']);
  });

  test('skips dependent agents when a prerequisite fails', () async {
    final orchestrator = SubagentOrchestrator(
      parentRequestId: 'request-2',
      conversationId: 'chat-2',
      onEvent: (_) {},
      execute: (task, dependencies, isCancelled) async { if (task.id == 'first') throw StateError('worker failed'); return 'unexpected'; },
    );
    final results = await orchestrator.run([
      const SubagentTask(id: 'first', title: 'First', prompt: 'First'),
      const SubagentTask(id: 'second', title: 'Second', prompt: 'Second', dependsOn: ['first']),
    ]);
    expect(results.map((r) => r.status), ['failed', 'skipped']);
  });

  test('can cancel one active child without cancelling its siblings', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    late SubagentOrchestrator orchestrator;
    orchestrator = SubagentOrchestrator(
      parentRequestId: 'request-targeted-cancel',
      conversationId: 'chat-targeted-cancel',
      maxConcurrency: 1,
      onEvent: (_) {},
      execute: (task, dependencies, isCancelled) async {
        if (!started.isCompleted) started.complete();
        await release.future;
        if (isCancelled()) {
          throw const SubagentInterrupted('targeted cancellation');
        }
        return 'finished';
      },
    );
    final run = orchestrator.run([
      const SubagentTask(id: 'active', title: 'Active', prompt: 'Active'),
      const SubagentTask(id: 'pending', title: 'Pending', prompt: 'Pending'),
    ]);
    await started.future;
    expect(orchestrator.cancelTask('active'), isTrue);
    expect(orchestrator.cancelTask('unknown'), isFalse);
    release.complete();
    final results = await run;
    expect(results.map((result) => result.status), ['cancelled', 'completed']);
  });

  test('records interrupted workers distinctly from failures', () async {
    final orchestrator = SubagentOrchestrator(
      parentRequestId: 'request-interrupted',
      conversationId: 'chat-interrupted',
      onEvent: (_) {},
      execute: (task, dependencies, isCancelled) async {
        throw const SubagentInterrupted('cancelled at safe boundary');
      },
    );
    final results = await orchestrator.run([
      const SubagentTask(
        id: 'worker',
        title: 'Worker',
        prompt: 'Work',
        agentType: 'explore',
      ),
    ]);
    expect(results.single.status, 'interrupted');
    expect(results.single.error, 'cancelled at safe boundary');
  });

  test('rejects duplicate ids, unknown dependencies and dependency cycles', () {
    final o = SubagentOrchestrator(parentRequestId: 'request-3', conversationId: 'chat-3', onEvent: (_) {}, execute: (task, dependencies, isCancelled) async => 'ok');
    expect(() => o.run([
      const SubagentTask(id: 'x', title: 'X', prompt: 'x'),
      const SubagentTask(id: 'x', title: 'X2', prompt: 'x2'),
    ]), throwsArgumentError);
    expect(() => o.run([
      const SubagentTask(id: 'x', title: 'X', prompt: 'x', dependsOn: ['missing']),
    ]), throwsArgumentError);
    expect(() => o.run([
      const SubagentTask(id: 'x', title: 'X', prompt: 'x', dependsOn: ['y']),
      const SubagentTask(id: 'y', title: 'Y', prompt: 'y', dependsOn: ['x']),
    ]), throwsArgumentError);
  });

  test('cancellation prevents pending tasks from starting', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    late SubagentOrchestrator o;
    o = SubagentOrchestrator(parentRequestId: 'request-4', conversationId: 'chat-4', maxConcurrency: 1, onEvent: (_) {}, execute: (task, dependencies, isCancelled) async {
      started.complete();
      await release.future;
      return 'done';
    });
    final run = o.run([
      const SubagentTask(id: 'one', title: 'One', prompt: 'one'),
      const SubagentTask(id: 'two', title: 'Two', prompt: 'two'),
    ]);
    await started.future;
    o.cancel();
    release.complete();
    final results = await run;
    expect(results.map((r) => r.status), ['completed', 'cancelled']);
  });
}
