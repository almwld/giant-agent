import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/widgets/voice_orb.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('approved glass orb asset keeps its embedded transparent animation', () async {
    final source = await rootBundle.loadString('assets/animations/voice_orb.json');
    final animation = jsonDecode(source) as Map<String, dynamic>;
    final assets = animation['assets'] as List<dynamic>;

    expect(animation['v'], '5.7.4');
    expect(animation['fr'], 60);
    expect(animation['w'], 640);
    expect(animation['h'], 360);
    expect(animation['op'], 600);
    expect(assets, hasLength(94));
    expect(
      assets.every((asset) =>
          asset is Map &&
          asset['p'] is String &&
          (asset['p'] as String).startsWith('data:image/webp;base64,')),
      isTrue,
    );
  });

  testWidgets('voice orb renders and responds to every voice state', (tester) async {
    for (final state in AgentState.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GlowingOrb(state: state, size: 220),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.byIcon(Icons.graphic_eq_rounded),
        findsNothing,
        reason: 'Lottie should load instead of the fallback for $state',
      );
      expect(tester.takeException(), isNull);
    }
  });
}
