import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/screens/pro_home_shell.dart';

void main() {
  testWidgets('chat is the landing tab and all six AgentsOS surfaces are in bottom navigation', (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(const MaterialApp(home: ProHomeShell()));

    expect(find.text('الدردشة'), findsOneWidget);
    expect(find.text('الرئيسية'), findsOneWidget);
    expect(find.text('المهام'), findsOneWidget);
    expect(find.text('الوكلاء'), findsOneWidget);
    expect(find.text('المقارنة'), findsOneWidget);
    expect(find.text('التكاملات'), findsOneWidget);
    expect(find.text('الإعدادات'), findsOneWidget);

    await tester.tap(find.text('المهام'));
    await tester.pump();
    expect(find.text('Task Manager'), findsOneWidget);

    await tester.tap(find.text('الدردشة'));
    await tester.pump();
    expect(find.byType(TextField), findsWidgets);

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
