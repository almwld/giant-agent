import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:giant_agent_x/widgets/global_voice_orb_overlay_host.dart';

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
}
