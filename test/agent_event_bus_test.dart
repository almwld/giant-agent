import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/agent/architecture/agent_event_bus.dart';

void main() {
  test('publishes JSON-safe events with request-scoped session identity', () async {
    final bus = AgentEventBus.instance;
    const requestId = 'bus-test-request';
    bus.bindRequest(requestId, 'session-a');
    final received = bus.events.first;

    bus.publish({
      'id': 'event-unique-1',
      'request_id': requestId,
      'type': 'tool_output',
      'title': 'Tool completed',
      'status': 'completed',
      'timestamp': DateTime.utc(2026, 11, 10),
      'metadata': {'attempt': 1, 'valid': true},
    });

    final event = await received;
    expect(event['session_id'], 'session-a');
    expect(event['attempt_id'], requestId);
    expect(event['sequence'], isA<int>());
    expect(event['timestamp'], '2026-11-10T00:00:00.000Z');
    expect(event['metadata'], {'attempt': 1, 'valid': true});
    expect(() => event['type'] = 'changed', throwsUnsupportedError);
    bus.unbindRequest(requestId);
  });

  test('generates an ID when a producer omits one', () async {
    final bus = AgentEventBus.instance;
    final received = bus.events.first;
    bus.publish({'type': 'diagnostic', 'title': 'Native diagnostic'});
    final event = await received;
    expect(event['id'], isA<String>());
    expect((event['id'] as String), isNotEmpty);
    expect(event['status'], 'pending');
    expect(event['sequence'], isA<int>());
  });
}
