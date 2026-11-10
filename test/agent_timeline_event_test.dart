import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/agent/architecture/agent_timeline_event.dart';

void main() {
  group('AgentTimelineEvent', () {
    test('round trips JSON-safe event metadata', () {
      final original = AgentTimelineEvent(
        id: 'event-2',
        requestId: 'request-1',
        attemptId: 'request-1',
        stepId: 'tool-call-1',
        sequence: 2,
        type: 'tool_output',
        title: 'Tool completed',
        status: 'completed',
        timestamp: DateTime.utc(2026, 11, 10, 12),
        details: 'Created file.',
      );

      final restored = AgentTimelineEvent.fromMap(original.toMap());

      expect(restored.id, original.id);
      expect(restored.requestId, original.requestId);
      expect(restored.attemptId, original.attemptId);
      expect(restored.stepId, original.stepId);
      expect(restored.sequence, original.sequence);
      expect(restored.type, original.type);
      expect(restored.status, original.status);
      expect(restored.timestamp, original.timestamp);
      expect(restored.details, original.details);
    });

    test('accepts persisted millisecond timestamps and numeric sequences', () {
      final event = AgentTimelineEvent.fromMap({
        'id': 'event-1',
        'request_id': 'request-1',
        'type': 'execution_started',
        'title': 'Started',
        'status': 'running',
        'timestamp': 1794312000000,
        'sequence': 7.0,
      });

      expect(event.timestamp.millisecondsSinceEpoch, 1794312000000);
      expect(event.sequence, 7);
      expect(event.attemptId, 'request-1');
    });

    test('uses safe defaults for malformed optional JSON fields', () {
      final event = AgentTimelineEvent.fromMap({
        'id': 'event-3',
        'timestamp': 'not-a-date',
        'sequence': 'not-a-number',
      });

      expect(event.requestId, isEmpty);
      expect(event.type, 'unknown');
      expect(event.status, 'pending');
      expect(event.sequence, isNull);
      expect(event.timestamp.millisecondsSinceEpoch, 0);
    });
  });
}
