import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/screens/agent_workflow_screen.dart';
import 'package:giant_agent_x/screens/pro_feature_directory.dart';

void main() {
  testWidgets('AgentOS tools directory exposes every supporting service', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(const MaterialApp(home: ProFeatureDirectoryScreen()));

    const destinations = [
      'Execution & workspace',
      'Agent workflow',
      'Workspace',
      'Model library',
      'Monitoring & diagnostics',
      'Live observability',
      'Engine performance',
      'Usage statistics',
      'Model benchmark',
      'Integrations & configuration',
      'MCP servers',
    ];
    for (final label in destinations) {
      await tester.scrollUntilVisible(
        find.text(label),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(label), findsOneWidget);
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('tools directory opens the existing workflow screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProFeatureDirectoryScreen()));

    await tester.tap(find.text('Agent workflow'));
    await tester.pumpAndSettle();

    expect(find.byType(AgentWorkflowScreen), findsOneWidget);
  });
}
