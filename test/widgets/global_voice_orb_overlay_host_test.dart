import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:giant_agent_x/widgets/global_voice_orb_overlay_host.dart';
import 'package:giant_agent_x/widgets/voice_session_overlay.dart';
import 'package:giant_agent_x/services/voice_session_controller.dart';

void main() {
  tearDown(GlobalVoiceOrbOverlayBridge.hide);

  testWidgets('voice orb remains above pushed AgentsOS routes', (tester) async {
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => GlobalVoiceOrbOverlayHost(
        child: child ?? const SizedBox.shrink(),
      ),
      home: Builder(builder: (context) => Scaffold(
        body: Center(child: ElevatedButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const Scaffold(
              body: Center(child: Text('AgentsOS control center')),
            ),
          )),
          child: const Text('Open AgentsOS'),
        )),
      )),
    ));

    GlobalVoiceOrbOverlayBridge.show(
      const Positioned(
        top: 12,
        right: 12,
        child: Material(
          color: Color(0xFF181D29),
          child: Padding(
            padding: EdgeInsets.all(8),
            child: Text('Global voice orb'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Global voice orb'), findsOneWidget);
    await tester.tap(find.text('Open AgentsOS'));
    await tester.pumpAndSettle();

    expect(find.text('AgentsOS control center'), findsOneWidget);
    expect(find.text('Global voice orb'), findsOneWidget);

    GlobalVoiceOrbOverlayBridge.hide();
    await tester.pump();
    expect(find.text('Global voice orb'), findsNothing);
  });

  testWidgets('app-owned voice overlay survives replacing the chat route', (tester) async {
    final session = VoiceSessionController.instance;
    session.state.value = const VoiceSessionSnapshot(
      active: true,
      isListening: true,
      phase: VoiceSessionPhase.listening,
    );

    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => GlobalVoiceOrbOverlayHost(
        child: child ?? const SizedBox.shrink(),
      ),
      home: Builder(builder: (context) => Scaffold(
        body: Center(child: ElevatedButton(
          onPressed: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(builder: (_) => const Scaffold(
              body: Center(child: Text('Another AgentsOS screen')),
            )),
          ),
          child: const Text('Leave chat'),
        )),
      )),
    ));

    GlobalVoiceOrbOverlayBridge.show(const VoiceSessionOverlay());
    await tester.pump();
    expect(find.text('أستمع إليك محلياً…'), findsOneWidget);

    await tester.tap(find.byTooltip('تصغير المساعد الصوتي'));
    await tester.pump();
    await tester.tap(find.text('Leave chat'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Another AgentsOS screen'), findsOneWidget);
    expect(find.text('أستمع إليك محلياً…'), findsOneWidget);
    expect(session.isActive, isTrue);
    expect(session.snapshot.isListening, isTrue);

    GlobalVoiceOrbOverlayBridge.hide();
    session.state.value = const VoiceSessionSnapshot();
    await tester.pump();
    expect(find.text('أستمع إليك محلياً…'), findsNothing);
  });

}
