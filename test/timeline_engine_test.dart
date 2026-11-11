import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent/core/timeline_engine.dart';
import 'package:giant_agent/core/tool_cancellation_manager.dart';

void main() {
  group('TimelineEngine', () {
    late TimelineEngine engine;

    setUp(() {
      engine = TimelineEngine(sessionId: 'session-test');
    });

    tearDown(() async {
      await engine.dispose();
    });

    test('adds and updates events in the correct session', () {
      final event = engine.add(
        type: TimelineEventType.toolStarted,
        title: 'Fetch data',
        status: TimelineStatus.running,
        toolCallId: 'call-1',
        progress: 0.2,
      );

      expect(engine.events, hasLength(1));
      expect(engine.events.single.sessionId, 'session-test');
      expect(engine.isRunning, isTrue);

      final updated = engine.update(
        event.id,
        status: TimelineStatus.completed,
        progress: 1,
        completedAt: DateTime.now(),
      );

      expect(updated?.status, TimelineStatus.completed);
      expect(updated?.progress, 1);
      expect(engine.isRunning, isFalse);
    });

    test('supports clearing nullable fields through copyWith update', () {
      final event = engine.add(
        type: TimelineEventType.toolFailed,
        title: 'Tool',
        status: TimelineStatus.failed,
        description: 'Details',
      );

      final updated = engine.update(
        event.id,
        description: null,
        error: null,
        progress: null,
      );

      expect(updated?.description, isNull);
      expect(updated?.error, isNull);
      expect(updated?.progress, isNull);
    });

    test('cancels every active event for a tool call id', () {
      engine.add(
        type: TimelineEventType.toolStarted,
        title: 'Tool started',
        status: TimelineStatus.running,
        toolCallId: 'call-2',
      );
      engine.add(
        type: TimelineEventType.toolProgress,
        title: 'Tool progress',
        status: TimelineStatus.waiting,
        toolCallId: 'call-2',
      );
      engine.add(
        type: TimelineEventType.toolCompleted,
        title: 'Already completed',
        status: TimelineStatus.completed,
        toolCallId: 'call-2',
      );

      expect(engine.cancelByToolCallId('call-2'), 2);
      expect(engine.events.where((e) => e.isActive), isEmpty);
      expect(engine.events.last.status, TimelineStatus.completed);
    });

    test('restore ignores events belonging to another session', () {
      final foreign = AgentTimelineEvent(
        id: 'foreign',
        sessionId: 'another-session',
        type: TimelineEventType.info,
        title: 'Foreign event',
        status: TimelineStatus.completed,
        createdAt: DateTime.now(),
      );
      engine.restore([foreign]);
      expect(engine.events, isEmpty);
    });

    test('normalizes invalid progress values', () {
      final event = engine.add(
        type: TimelineEventType.toolProgress,
        title: 'Progress',
        progress: double.nan,
      );
      expect(event.progress, isNull);
      final updated = engine.update(event.id, progress: 1.7);
      expect(updated?.progress, 1);
    });
  });

  group('ToolCancellationManager', () {
    late ToolCancellationManager manager;

    setUp(() => manager = ToolCancellationManager());
    tearDown(() async => manager.dispose());

    test('cancellation wakes a cooperative delay with the reason', () async {
      final token = manager.registerTool('call-cancel');
      final operation = token.delay(const Duration(seconds: 30));
      await manager.cancelTool('call-cancel', reason: 'User stopped it');

      await expectLater(
        operation,
        throwsA(isA<ToolCancelledException>()
            .having((e) => e.reason, 'reason', 'User stopped it')),
      );
    });

    test('unregister only removes the expected token', () {
      final first = manager.registerTool('call-reuse');
      manager.unregisterTool('call-reuse', expected: first);
      final second = manager.registerTool('call-reuse');
      manager.unregisterTool('call-reuse', expected: first);
      expect(manager.tokenFor('call-reuse'), same(second));
    });
  });
}
