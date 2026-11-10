import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/agent/architecture/agent_timeline_event.dart';

void main() {
  group('AgentTimelineEvent', () {
    test('serializes stable lifecycle metadata for the timeline', () {
      final timestamp = DateTime.utc(2026, 11, 5, 7, 0);
      final event = AgentTimelineEvent(
        id: 'kernel_request-1_1',
        requestId: 'request-1',
        type: 'execution_started',
        title: 'بدأ تنفيذ الطلب',
        status: 'running',
        timestamp: timestamp,
        details: 'تم قبول الطلب وبدء التنفيذ.',
      );

      expect(event.toMap(), {
        'id': 'kernel_request-1_1',
        'request_id': 'request-1',
        'attempt_id': 'request-1',
        'type': 'execution_started',
        'title': 'بدأ تنفيذ الطلب',
        'status': 'running',
        'timestamp': timestamp.toIso8601String(),
        'details': 'تم قبول الطلب وبدء التنفيذ.',
      });
    });

    test('round-trips child agent identity and role', () {
      final event = AgentTimelineEvent(
        id: 'child-event-1',
        requestId: 'parent-request',
        type: 'subagent_started',
        title: 'بدأ وكيل الاستكشاف',
        status: 'running',
        timestamp: DateTime.utc(2026, 11, 10),
        taskId: 'parent-request_agent_explore',
        agentType: 'explore',
      );

      final restored = AgentTimelineEvent.fromMap(event.toMap());
      expect(restored.taskId, 'parent-request_agent_explore');
      expect(restored.agentType, 'explore');
    });

    test('omits absent optional details', () {
      final event = AgentTimelineEvent(
        id: 'kernel_runtime_1',
        requestId: 'runtime',
        type: 'runtime_ready',
        title: 'محرك الوكيل جاهز',
        status: 'completed',
        timestamp: DateTime.utc(2026, 11, 5),
      );

      expect(event.toMap().containsKey('details'), isFalse);
      expect(event.toMap()['status'], 'completed');
    });
  });
}
