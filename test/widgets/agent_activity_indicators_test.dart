import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/widgets/agent_activity_indicators.dart';

void main() {
  testWidgets('agent activity indicators render and animate safely',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AgentPulseDot(),
              AgentThinkingDots(),
              AgentShimmerText(
                'يكتب الوكيل الرد النهائي',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('يكتب الوكيل الرد النهائي'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(AgentPulseDot), findsOneWidget);
    expect(find.byType(AgentThinkingDots), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
