import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/screens/pro_agentsos_hub.dart';

void main() {
  setUp(() {
    // Keep the control-center singleton isolated from previous widget tests.
  });

  testWidgets('AgentsOS exposes all six destinations and renders each screen', (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: ProAgentsOsHub()));
    await tester.pumpAndSettle();

    expect(find.byType(BottomNavigationBar), findsOneWidget);
    for (final label in ['Dashboard', 'Tasks', 'Agents', 'Battle', 'Integrations', 'Config']) {
      expect(find.text(label), findsOneWidget, reason: 'Missing AgentsOS destination: $label');
    }

    final destinations = <String, String>{
      'Dashboard': 'Operational Control Center',
      'Tasks': 'Task Manager',
      'Agents': 'Agent Fleet Overview',
      'Battle': 'Battle-card Hub',
      'Integrations': 'No MCP integrations configured yet.',
      'Config': 'Advanced Configuration',
    };

    for (final entry in destinations.entries) {
      await tester.tap(find.text(entry.key).first);
      await tester.pumpAndSettle();
      expect(
        find.text(entry.value),
        findsOneWidget,
        reason: 'The ${entry.key} destination did not render its expected screen content.',
      );
      expect(tester.takeException(), isNull, reason: 'The ${entry.key} screen threw during rendering.');
    }
  });

  testWidgets('AgentsOS retains the selected destination when rebuilding its shell', (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: ProAgentsOsHub()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tasks').first);
    await tester.pumpAndSettle();
    expect(find.text('Task Manager'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: ProAgentsOsHub()));
    await tester.pumpAndSettle();
    expect(find.text('Operational Control Center'), findsOneWidget);
  });
}
