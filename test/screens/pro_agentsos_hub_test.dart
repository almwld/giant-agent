import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/screens/pro_agentsos_hub.dart';
import 'package:giant_agent_x/screens/pro_dashboard.dart';
import 'package:giant_agent_x/screens/pro_task_manager.dart';
import 'package:giant_agent_x/screens/pro_agent_fleet.dart';
import 'package:giant_agent_x/screens/pro_battle_card.dart';
import 'package:giant_agent_x/screens/pro_integrations.dart';
import 'package:giant_agent_x/screens/pro_advanced_config.dart';

void main() {
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

    final destinations = <String, Type>{
      'Dashboard': ProDashboard,
      'Tasks': ProTaskManager,
      'Agents': ProAgentFleet,
      'Battle': ProBattleCard,
      'Integrations': ProIntegrations,
      'Config': ProAdvancedConfig,
    };

    for (final entry in destinations.entries) {
      await tester.tap(find.text(entry.key).first);
      await tester.pumpAndSettle();
      expect(
        find.byType(entry.value),
        findsOneWidget,
        reason: 'The ${entry.key} destination did not mount its screen.',
      );
      expect(tester.takeException(), isNull, reason: 'The ${entry.key} screen threw during rendering.');
    }
  });

  testWidgets('AgentsOS retains the selected destination when its parent rebuilds', (tester) async {
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
    expect(find.text('Task Manager'), findsOneWidget);
  });
}
