import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/services/voice_session_controller.dart';

void main() {
  final session = VoiceSessionController.instance;

  tearDown(() {
    session.detach();
    session.state.value = const VoiceSessionSnapshot();
  });

  test('detaching a route does not terminate the app-scoped voice session', () {
    session.state.value = const VoiceSessionSnapshot(
      active: true,
      isListening: true,
      phase: VoiceSessionPhase.listening,
    );

    session.attach(onSpeechEnded: () async {});
    expect(session.hasAttachedScreen, isTrue);

    session.detach();

    expect(session.hasAttachedScreen, isFalse);
    expect(session.isActive, isTrue);
    expect(session.snapshot.isListening, isTrue);
    expect(session.snapshot.phase, VoiceSessionPhase.listening);
  });

  test('a reattached chat screen can receive the pending session callback', () {
    var calls = 0;
    session.attach(onSpeechEnded: () async { calls++; });
    expect(session.hasAttachedScreen, isTrue);
    session.detach();
    session.attach(onSpeechEnded: () async { calls++; });
    expect(session.hasAttachedScreen, isTrue);
    expect(calls, 0);
  });
}
