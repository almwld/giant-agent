import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/screens/pro_agentsos_detail_screens.dart';
import 'package:giant_agent_x/domain/kernel/agent_kernel_store.dart';

void main() {
  testWidgets('task details expose persisted lifecycle, step, result and recovery data', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ProTaskDetailScreen(task: {
        'id': 'task-1',
        'description': 'Prepare report',
        'status': 'paused',
        'conversation_id': 'conversation-1',
        'recovery_note': 'Review side effects before resume.',
        'result': 'Partial result',
        'steps': [
          {'step': 1, 'action': 'Collect sources', 'status': 'uncertain', 'recovery_state': 'side_effect_unknown'}
        ],
      }),
    ));

    expect(find.text('Prepare report'), findsOneWidget);
    expect(find.text('task-1'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Partial result'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Partial result'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Collect sources'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Collect sources'), findsOneWidget);
    expect(find.textContaining('side_effect_unknown'), findsOneWidget);
  });

  testWidgets('task details expose a route to persisted lifecycle history', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ProTaskDetailScreen(task: {
        'id': 'task-history-1',
        'description': 'Run production checks',
        'status': 'completed',
        'steps': [],
      }),
    ));
    await tester.scrollUntilVisible(
      find.text('Open persisted task lifecycle history'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Open persisted task lifecycle history'), findsOneWidget);
  });

  testWidgets('task event history shows lifecycle metadata without payload contents', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ProTaskEventHistoryScreen(
        taskTitle: 'Run production checks',
        events: [
          KernelEventRecord(
            id: 'task-event-1',
            requestId: 'request-1',
            type: 'task_completed',
            status: 'completed',
            payload: const {'private_result': 'must not be rendered in the task timeline'},
            createdAt: DateTime.utc(2026, 11, 17),
          ),
        ],
      ),
    ));
    expect(find.text('task completed'), findsOneWidget);
    expect(find.textContaining('must not be rendered in the task timeline'), findsNothing);
  });

  testWidgets('agent details display only fields from the persisted snapshot', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ProAgentDetailScreen(agent: {
        'agent_id': 'researcher',
        'task_id': 'subtask-2',
        'status': 'completed',
        'title': 'Research worker',
      }),
    ));

    // The title/status appear in both the summary header and raw persisted
    // record, making their provenance visible in both contexts.
    expect(find.text('Research worker'), findsNWidgets(2));
    expect(find.text('researcher'), findsOneWidget);
    expect(find.text('subtask-2'), findsOneWidget);
    expect(find.text('completed'), findsNWidgets(2));
  });

  testWidgets('agent event history shows lifecycle metadata without payload contents', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ProAgentEventHistoryScreen(
        agentTitle: 'Research worker',
        events: [
          KernelEventRecord(
            id: 'event-1',
            requestId: 'request-1',
            type: 'subagent_completed',
            status: 'completed',
            payload: const {'private_result': 'must not be rendered in the timeline'},
            createdAt: DateTime.utc(2026, 11, 16),
          ),
        ],
      ),
    ));

    expect(find.text('subagent completed'), findsOneWidget);
    expect(find.textContaining('completed'), findsNWidgets(2));
    expect(find.textContaining('must not be rendered in the timeline'), findsNothing);
  });
}
