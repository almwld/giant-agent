import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/agent/architecture/subagent_orchestrator.dart';

void main() {
  test('runs independent agents concurrently and respects dependencies', () async {
    final active = <String>{};
    var peak = 0;
    final events = <Map<String, Object?>>[];
    final orchestrator = SubagentOrchestrator(
      maxConcurrency: 2,
      onEvent: events.add,
      execute: (task) async {
        active.add(task.id);
        if (active.length > peak) peak = active.length;
        await Future<void>.delayed(const Duration(milliseconds: 15));
        active.remove(task.id);
        return 'result-${task.id}';
      },
    );
    final results = await orchestrator.run([
      const SubagentTask(id: 'research', title: 'Research', prompt: 'Research'),
      const SubagentTask(id: 'audit', title: 'Audit', prompt: 'Audit'),
      const SubagentTask(id: 'synthesis', title: 'Synthesis', prompt: 'Synthesize', dependsOn: ['research', 'audit']),
    ]);
    expect(peak, 2);
    expect(results.map((r) => r.status), ['completed', 'completed', 'completed']);
    expect(results.last.output, 'result-synthesis');
    expect(events.map((e) => e['type']), contains('subagent_completed'));
  });

  test('skips dependent agents when a prerequisite fails', () async {
    final orchestrator = SubagentOrchestrator(
      onEvent: (_) {},
      execute: (task) async { if (task.id == 'first') throw StateError('worker failed'); return 'unexpected'; },
    );
    final results = await orchestrator.run([
      const SubagentTask(id: 'first', title: 'First', prompt: 'First'),
      const SubagentTask(id: 'second', title: 'Second', prompt: 'Second', dependsOn: ['first']),
    ]);
    expect(results.map((r) => r.status), ['failed', 'skipped']);
  });

  test('rejects duplicate ids, unknown dependencies and dependency cycles', () {
    final o = SubagentOrchestrator(onEvent: (_) {}, execute: (_) async => 'ok');
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
    o = SubagentOrchestrator(maxConcurrency: 1, onEvent: (_) {}, execute: (_) async {
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
