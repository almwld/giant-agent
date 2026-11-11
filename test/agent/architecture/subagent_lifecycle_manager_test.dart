import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/agent/architecture/subagent_lifecycle_manager.dart';

void main() {
  test('create registers an idle child without starting execution', () async {
    final events = <Map<String, Object?>>[];
    final manager = SubagentLifecycleManager(onEvent: events.add);

    final child = await manager.create(
      requestId: 'request-1',
      conversationId: 'chat-1',
      id: 'research',
      title: 'Research',
      prompt: 'Inspect the repository.',
      agentType: 'explore',
    );

    expect(child.status, 'idle');
    expect(child.wireStatus, 'STATUS_IDLE');
    expect(events.single['type'], 'subagent_created');
    expect(events.single['status'], 'idle');
  });

  test('dependencies must complete before a child can spawn', () async {
    final manager = SubagentLifecycleManager(onEvent: (_) {});
    await manager.create(
      requestId: 'request-2',
      conversationId: 'chat-2',
      id: 'first',
      title: 'First',
      prompt: 'First task',
      agentType: 'explore',
    );
    await manager.create(
      requestId: 'request-2',
      conversationId: 'chat-2',
      id: 'second',
      title: 'Second',
      prompt: 'Second task',
      agentType: 'reviewer',
      dependsOn: const ['first'],
    );

    await expectLater(manager.start('request-2', 'second'), throwsStateError);
    await manager.start('request-2', 'first');
    await manager.complete('request-2', 'first', 'verified result');
    await manager.start('request-2', 'second');
    await manager.complete('request-2', 'second', 'review complete');

    expect(manager.get('request-2', 'second')!.status, 'completed');
    expect(manager.get('request-2', 'second')!.progressPercent, 100);
    expect(manager.get('request-2', 'second')!.wireStatus, 'STATUS_TERMINATED');
  });

  test('rejects duplicate ids, invalid roles and unknown dependencies', () async {
    final manager = SubagentLifecycleManager(onEvent: (_) {});
    Future<void> create(String id, {String role = 'explore', List<String> deps = const []}) async {
      await manager.create(
        requestId: 'request-3',
        conversationId: 'chat-3',
        id: id,
        title: id,
        prompt: 'Task $id',
        agentType: role,
        dependsOn: deps,
      );
    }

    await create('one');
    await expectLater(create('one'), throwsStateError);
    await expectLater(create('two', role: 'unknown'), throwsArgumentError);
    await expectLater(create('three', deps: const ['missing']), throwsArgumentError);
  });

  test('delete is a soft dismissal and preserves terminal history', () async {
    final events = <Map<String, Object?>>[];
    final manager = SubagentLifecycleManager(onEvent: events.add);
    await manager.create(
      requestId: 'request-4',
      conversationId: 'chat-4',
      id: 'pending',
      title: 'Pending',
      prompt: 'Not started',
      agentType: 'plan',
    );

    await manager.delete('request-4', 'pending');
    final child = manager.get('request-4', 'pending')!;

    expect(child.status, 'cancelled');
    expect(child.dismissed, isTrue);
    expect(events.map((event) => event['type']),
        containsAllInOrder(['subagent_created', 'subagent_cancelled', 'subagent_dismissed']));
  });

  test('mailbox delivers queued messages and wakes a waiter', () async {
    final events = <Map<String, Object?>>[];
    final manager = SubagentLifecycleManager(onEvent: events.add);
    await manager.create(
      requestId: 'request-5',
      conversationId: 'chat-5',
      id: 'worker',
      title: 'Worker',
      prompt: 'Wait for instructions',
      agentType: 'explore',
    );

    await manager.sendMessage(
      requestId: 'request-5',
      agentId: 'worker',
      message: 'Inspect recovery tests.',
    );
    final queued = await manager.waitForMessage(
      requestId: 'request-5',
      agentId: 'worker',
      timeoutSeconds: 1,
    );
    expect(queued?['message'], 'Inspect recovery tests.');
    expect(queued?['message_id'], isNotEmpty);
    final sentEvent = events.firstWhere((event) => event['type'] == 'subagent_message_sent');
    final receivedEvent = events.firstWhere((event) => event['type'] == 'subagent_message_received');
    expect(sentEvent['message'], 'Inspect recovery tests.');
    expect(receivedEvent['message_id'], queued?['message_id']);

    final pending = manager.waitForMessage(
      requestId: 'request-5',
      agentId: 'worker',
      timeoutSeconds: 2,
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await manager.sendMessage(
      requestId: 'request-5',
      agentId: 'worker',
      message: 'Now inspect MCP.',
    );
    final delivered = await pending;
    expect(delivered?['message'], 'Now inspect MCP.');
  });

  test('goal updates are scoped to the parent request', () async {
    final events = <Map<String, Object?>>[];
    final manager = SubagentLifecycleManager(onEvent: events.add);
    await manager.updateGoal('request-6', 'Finish integration and verify tests.');

    expect(manager.currentGoal('request-6'), 'Finish integration and verify tests.');
    expect(events.single['type'], 'goal_updated');
    expect(events.single['request_id'], 'request-6');
    expect(events.single['goal'], 'Finish integration and verify tests.');
  });

  test('running children cannot be deleted or silently erased', () async {
    final manager = SubagentLifecycleManager(onEvent: (_) {});
    await manager.create(
      requestId: 'request-7',
      conversationId: 'chat-7',
      id: 'active',
      title: 'Active',
      prompt: 'Run task',
      agentType: 'coder',
    );
    await manager.start('request-7', 'active');
    await expectLater(manager.delete('request-7', 'active'), throwsStateError);
    expect(manager.get('request-7', 'active')!.status, 'running');
  });
  test('mailbox wait exits promptly when its exact tool call is cancelled', () async {
    final manager = SubagentLifecycleManager(onEvent: (_) {});
    await manager.create(
      requestId: 'request-cancel',
      conversationId: 'chat-cancel',
      id: 'worker',
      title: 'Worker',
      prompt: 'Wait for a message',
      agentType: 'explore',
    );
    var cancelled = false;
    final waiting = manager.waitForMessage(
      requestId: 'request-cancel',
      agentId: 'worker',
      timeoutSeconds: 10,
      isCancelled: () => cancelled,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    cancelled = true;
    await expectLater(waiting, throwsStateError);

    await manager.sendMessage(
      requestId: 'request-cancel',
      agentId: 'worker',
      message: 'The cancelled waiter was removed.',
    );
    final next = await manager.waitForMessage(
      requestId: 'request-cancel',
      agentId: 'worker',
      timeoutSeconds: 1,
    );
    expect(next?['message'], 'The cancelled waiter was removed.');
  });

  test('restores durable child state, latest goal and only undelivered mailbox messages', () async {
    final originalEvents = <Map<String, Object?>>[];
    final original = SubagentLifecycleManager(onEvent: originalEvents.add);
    await original.create(
      requestId: 'request-restore',
      conversationId: 'chat-restore',
      id: 'worker',
      title: 'Worker',
      prompt: 'Recover this task',
      agentType: 'explore',
    );
    await original.sendMessage(
      requestId: 'request-restore',
      agentId: 'worker',
      message: 'Already consumed',
    );
    await original.waitForMessage(
      requestId: 'request-restore',
      agentId: 'worker',
      timeoutSeconds: 1,
    );
    await original.sendMessage(
      requestId: 'request-restore',
      agentId: 'worker',
      message: 'Still waiting for delivery',
    );
    await original.updateGoal(
      'request-restore',
      'Finish the recovery work and verify its result.',
    );

    final restored = SubagentLifecycleManager(onEvent: (_) {});
    restored.restore(
      requestId: 'request-restore',
      conversationId: 'chat-restore',
      snapshots: [
        <String, Object?>{
          'id': 'request-restore_dynamic_worker',
          'parent_request_id': 'request-restore',
          'conversation_id': 'chat-restore',
          'title': 'Worker',
          'task_prompt': 'Recover this task',
          'agent_type': 'explore',
          'depends_on': const <String>[],
          'status': 'interrupted',
          'progress_percent': 40,
          'created_at': DateTime.utc(2026, 11, 12).toIso8601String(),
          'is_dismissed': false,
        },
      ],
      events: originalEvents,
    );

    final child = restored.get('request-restore', 'worker');
    expect(child, isNotNull);
    expect(child!.status, 'interrupted');
    expect(child.progressPercent, 40);
    expect(
      restored.currentGoal('request-restore'),
      'Finish the recovery work and verify its result.',
    );
    final pending = await restored.waitForMessage(
      requestId: 'request-restore',
      agentId: 'worker',
      timeoutSeconds: 1,
    );
    expect(pending?['message'], 'Still waiting for delivery');
  });

  test('draining a child mailbox records message consumption', () async {
    final events = <Map<String, Object?>>[];
    final manager = SubagentLifecycleManager(onEvent: events.add);
    await manager.create(
      requestId: 'request-drain',
      conversationId: 'chat-drain',
      id: 'worker',
      title: 'Worker',
      prompt: 'Read queued messages',
      agentType: 'explore',
    );
    await manager.sendMessage(
      requestId: 'request-drain',
      agentId: 'worker',
      message: 'Read the architecture map.',
    );

    final drained = await manager.drainMessages('request-drain', 'worker');
    expect(drained.single['message'], 'Read the architecture map.');
    expect(
      events.lastWhere((event) => event['type'] == 'subagent_message_received')['message_id'],
      drained.single['message_id'],
    );
  });

}
