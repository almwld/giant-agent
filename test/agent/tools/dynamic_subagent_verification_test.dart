import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/domain/harness/evaluator_service.dart';

void main() {
  final evaluator = EvaluatorService(
    readWorkspaceFile: (path) async => <String, dynamic>{'ok': true, 'path': path, 'content': ''},
  );

  test('verifies dynamic child registration and completion', () async {
    final created = await evaluator.verify(
      'delegate work',
      'create_subagent',
      const <String, dynamic>{'id': 'research'},
      <String, dynamic>{
        'ok': true,
        'subagent': <String, dynamic>{'id': 'research', 'status': 'idle'},
      },
    );
    expect(created.passed, isTrue);

    final spawned = await evaluator.verify(
      'delegate work',
      'spawn_subagent',
      const <String, dynamic>{'id': 'research'},
      <String, dynamic>{
        'ok': true,
        'subagent': <String, dynamic>{
          'id': 'research',
          'status': 'completed',
          'result': 'Evidence collected.',
        },
      },
    );
    expect(spawned.passed, isTrue);
  });

  test('rejects a child that did not complete with a result', () async {
    final result = await evaluator.verify(
      'delegate work',
      'spawn_subagent',
      const <String, dynamic>{'id': 'research'},
      <String, dynamic>{
        'ok': true,
        'subagent': <String, dynamic>{'id': 'research', 'status': 'failed'},
      },
    );
    expect(result.passed, isFalse);
  });

  test('verifies soft dismissal and status snapshots', () async {
    final deleted = await evaluator.verify(
      'remove from active list',
      'delete_subagent',
      const <String, dynamic>{'id': 'research'},
      <String, dynamic>{
        'ok': true,
        'subagent': <String, dynamic>{'id': 'research', 'dismissed': true},
      },
    );
    expect(deleted.passed, isTrue);

    final checked = await evaluator.verify(
      'check child',
      'check_subagent_status',
      const <String, dynamic>{'id': 'research'},
      <String, dynamic>{
        'ok': true,
        'subagent': <String, dynamic>{'id': 'research', 'status': 'completed'},
      },
    );
    expect(checked.passed, isTrue);
  });

  test('verifies mailbox, user input and goal update outcomes', () async {
    final sent = await evaluator.verify(
      'message child',
      'send_message',
      const <String, dynamic>{'agent_id': 'research'},
      const <String, dynamic>{'ok': true, 'message_queued': true, 'agent_id': 'research'},
    );
    expect(sent.passed, isTrue);

    final timeout = await evaluator.verify(
      'wait',
      'wait_for_message',
      const <String, dynamic>{'agent_id': 'research'},
      const <String, dynamic>{'ok': true, 'received': false, 'timed_out': true},
    );
    expect(timeout.passed, isTrue);

    final answered = await evaluator.verify(
      'clarify',
      'ask_user',
      const <String, dynamic>{},
      const <String, dynamic>{'ok': true, 'cancelled': false, 'answer': 'integration'},
    );
    expect(answered.passed, isTrue);

    final cancelled = await evaluator.verify(
      'clarify',
      'ask_user',
      const <String, dynamic>{},
      const <String, dynamic>{'ok': true, 'cancelled': true},
    );
    expect(cancelled.passed, isTrue);

    final goal = await evaluator.verify(
      'update',
      'update_goal',
      const <String, dynamic>{'goal': 'finish tests'},
      const <String, dynamic>{'ok': true, 'goal': 'finish tests'},
    );
    expect(goal.passed, isTrue);
  });
}
