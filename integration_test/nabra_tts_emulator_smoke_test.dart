import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:giant_agent_x/main.dart' as app;
import 'package:giant_agent_x/services/local_arabic_tts_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Nabra installs, initializes, synthesizes Arabic and plays locally',
      (tester) async {
    await app.main();
    await tester.pump();

    final tts = LocalArabicTtsService.instance;
    if (!await tts.isInstalled()) {
      await tts.install(
        onProgress: (file, fraction) => print(
          'NABRA_MODEL_DOWNLOAD: $file ${(fraction * 100).toStringAsFixed(1)}%',
        ),
      ).timeout(const Duration(minutes: 12));
    }
    expect(await tts.isInstalled(), isTrue);

    final stopwatch = Stopwatch()..start();
    await tts.initialize().timeout(const Duration(minutes: 2));
    print('NABRA_INITIALIZE_OK');
    await tts.speak('مرحباً، هذا اختبار تشغيل نموذج نبرا العربي محلياً.')
        .timeout(const Duration(minutes: 3));
    stopwatch.stop();

    print('NABRA_SYNTHESIS_AND_PLAYBACK_OK: ${stopwatch.elapsedMilliseconds}ms');
    expect(tts.isReady, isTrue);
    await tts.dispose();
  });
}
