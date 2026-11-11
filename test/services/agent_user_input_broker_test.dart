import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/agent/architecture/agent_event_bus.dart';
import 'package:giant_agent_x/services/agent_user_input_broker.dart';

void main() {
  test('correlates a chat answer to the waiting worker request', () async {
    final requested = Completer<Map<String, dynamic>>();
    final subscription = AgentEventBus.instance.events.listen((event) {
      if (event['type'] == 'user_input_requested' && !requested.isCompleted) {
        requested.complete(Map<String, dynamic>.from(event));
      }
    });
    try {
      final answerFuture = AgentUserInputBroker.instance.askUser(
        requestId: 'request-1',
        taskId: 'worker-1',
        sessionId: 'chat-1',
        question: 'Choose option A or B.',
        timeout: const Duration(seconds: 2),
      );
      final event = await requested.future;
      expect(event['request_id'], 'request-1');
      expect(event['task_id'], 'worker-1');
      expect(event['session_id'], 'chat-1');
      expect(AgentUserInputBroker.instance.submitAnswer(
        event['input_request_id'] as String, 'Option A',
      ), isTrue);
      expect(await answerFuture, 'Option A');
      expect(AgentUserInputBroker.instance.pendingCount, 0);
    } finally {
      await subscription.cancel();
    }
  });

  test('returns null when the parent cancels a pending user question', () async {
    var cancelled = false;
    final answerFuture = AgentUserInputBroker.instance.askUser(
      requestId: 'request-cancel',
      taskId: 'worker-cancel',
      sessionId: 'chat-cancel',
      question: 'Need a decision?',
      timeout: const Duration(seconds: 2),
      isCancelled: () => cancelled,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    cancelled = true;
    expect(await answerFuture, isNull);
    expect(AgentUserInputBroker.instance.pendingCount, 0);
  });

  test('returns null when the user input deadline expires', () async {
    final answer = await AgentUserInputBroker.instance.askUser(
      requestId: 'request-timeout',
      taskId: 'worker-timeout',
      sessionId: 'chat-timeout',
      question: 'Please respond.',
      timeout: const Duration(milliseconds: 20),
    );
    expect(answer, isNull);
    expect(AgentUserInputBroker.instance.pendingCount, 0);
  });
}
