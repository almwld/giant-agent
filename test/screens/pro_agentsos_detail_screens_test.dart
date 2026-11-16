import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/screens/pro_agentsos_detail_screens.dart';

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
    expect(find.text('Review side effects before resume.'), findsOneWidget);
    expect(find.text('Partial result'), findsOneWidget);
    expect(find.textContaining('Collect sources'), findsOneWidget);
    expect(find.textContaining('side_effect_unknown'), findsOneWidget);
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
}
