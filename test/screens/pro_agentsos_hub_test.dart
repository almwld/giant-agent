import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/screens/pro_agentsos_hub.dart';

void main() {
  testWidgets('AgentsOS keeps six destinations in one persistent navigation shell', (tester) async {
    await tester.view.setPhysicalSize(const Size(900, 1200));
    await tester.view.setDevicePixelRatio(1);
    await tester.pumpWidget(const MaterialApp(home: ProAgentsOsHub()));

    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Agents'), findsOneWidget);
    expect(find.text('Battle'), findsOneWidget);
    expect(find.text('Integrations'), findsOneWidget);
    expect(find.text('Config'), findsOneWidget);

    await tester.tap(find.text('Tasks'));
    await tester.pump();
    expect(find.text('Task Manager'), findsOneWidget);

    await tester.tap(find.text('Agents'));
    await tester.pump();
    expect(find.text('Agent Fleet Overview'), findsOneWidget);

    await tester.view.resetPhysicalSize();
    await tester.view.resetDevicePixelRatio();
  });
}
