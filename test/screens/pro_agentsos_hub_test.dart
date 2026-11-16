import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/screens/pro_agentsos_hub.dart';

void main() {
  testWidgets('AgentsOS keeps six destinations in one persistent navigation shell', (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(const MaterialApp(home: ProAgentsOsHub()));

    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Agents'), findsOneWidget);
    expect(find.text('Battle'), findsOneWidget);
    expect(find.text('Integrations'), findsOneWidget);
    expect(find.text('Config'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.byType(BottomNavigationBar))).colorScheme.primary,
      const Color(0xFF0A8F83),
    );
    expect(
      Theme.of(tester.element(find.byType(BottomNavigationBar))).scaffoldBackgroundColor,
      const Color(0xFF111111),
    );

    await tester.tap(find.text('Tasks'));
    await tester.pump();
    expect(find.text('Task Manager'), findsOneWidget);

    await tester.tap(find.text('Agents'));
    await tester.pump();
    expect(find.text('Agent Fleet Overview'), findsOneWidget);

    await tester.tap(find.text('Battle').first);
    await tester.pump();
    expect(find.text('Battle Cards'), findsOneWidget);

    await tester.tap(find.text('Integrations').first);
    await tester.pump();
    expect(find.text('Integrations'), findsWidgets);

    await tester.tap(find.text('Config').first);
    await tester.pump();
    expect(find.text('Advanced Configuration'), findsOneWidget);

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
