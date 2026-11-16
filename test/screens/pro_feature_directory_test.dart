import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/screens/agent_workflow_screen.dart';
import 'package:giant_agent_x/screens/pro_feature_directory.dart';

void main() {
  testWidgets('AgentOS tools directory exposes every supporting service', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProFeatureDirectoryScreen()));

    expect(find.text('Execution & workspace'), findsOneWidget);
    expect(find.text('Monitoring & diagnostics'), findsOneWidget);
    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('Agent workflow'), findsOneWidget);
    expect(find.text('Workspace'), findsOneWidget);
    expect(find.text('Model library'), findsOneWidget);
    expect(find.text('Live observability'), findsOneWidget);
    expect(find.text('Engine performance'), findsOneWidget);
    expect(find.text('Usage statistics'), findsOneWidget);
    expect(find.text('Model benchmark'), findsOneWidget);
    expect(find.text('Advanced app settings'), findsOneWidget);
  });

  testWidgets('tools directory opens the existing workflow screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProFeatureDirectoryScreen()));

    await tester.tap(find.text('Agent workflow'));
    await tester.pumpAndSettle();

    expect(find.byType(AgentWorkflowScreen), findsOneWidget);
  });
}
