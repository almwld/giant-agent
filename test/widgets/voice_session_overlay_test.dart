import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:giant_agent_x/services/voice_session_controller.dart';
import 'package:giant_agent_x/widgets/voice_session_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final session = VoiceSessionController.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'giant_voice_orb_size': 210.0,
    });
    session.state.value = const VoiceSessionSnapshot(
      active: true,
      phase: VoiceSessionPhase.listening,
      isListening: true,
    );
  });

  tearDown(() {
    session.detach();
    session.state.value = const VoiceSessionSnapshot();
  });

  testWidgets('restores the saved full-screen voice orb size', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(children: [VoiceSessionOverlay()]),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, 210.0);
  });

  testWidgets('persists a changed full-screen voice orb size', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(children: [VoiceSessionOverlay()]),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    await tester.drag(find.byType(Slider), const Offset(65, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getDouble('giant_voice_orb_size'),
      isNot(210.0),
    );
  });
}
