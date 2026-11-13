import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/screens/pro_agentsos_hub.dart';

void main() {
  testWidgets('AgentsOS hub exposes all six control-center destinations', (tester) async {
    await tester.view.setPhysicalSize(const Size(900, 1200));
    await tester.view.setDevicePixelRatio(1);
    await tester.pumpWidget(const MaterialApp(home: ProAgentsOsHub()));
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Task Manager'), findsOneWidget);
    expect(find.text('Agent Fleet'), findsOneWidget);
    expect(find.text('Battle Cards'), findsOneWidget);
    expect(find.text('Integrations'), findsOneWidget);
    expect(find.text('Advanced Configuration'), findsOneWidget);
    await tester.view.resetPhysicalSize();
    await tester.view.resetDevicePixelRatio();
  });
}
