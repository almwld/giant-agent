import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:giant_agent_x/main.dart' as app;
import 'package:giant_agent_x/services/local_speech_recognition_service.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Whisper verifies multilingual Base, loads JNI and transcribes Arabic WAV locally',
    (tester) async {
      await app.main();
      await tester.pump();

      final speech = LocalSpeechRecognitionService.instance;
      await speech.initialize(
        onProgress: (fraction) =>
            print('WHISPER_MODEL_DOWNLOAD: ${(fraction * 100).toStringAsFixed(1)}%'),
      ).timeout(const Duration(minutes: 8));
      expect(speech.isModelReady, isTrue);
      print('WHISPER_NATIVE_INIT_OK: multilingual ggml-base.bin loaded');

      final fixture = await rootBundle.load(
        'integration_test/fixtures/arabic_smoke.wav',
      );
      final temp = await getTemporaryDirectory();
      final wav = File('${temp.path}/giant-agent-arabic-smoke.wav');
      await wav.writeAsBytes(
        fixture.buffer.asUint8List(
          fixture.offsetInBytes,
          fixture.lengthInBytes,
        ),
        flush: true,
      );

      try {
        print('WHISPER_INFERENCE_START: reusing initialized native context');
        final result = await speech
            .transcribeFile(wav.path, threads: 2)
            .timeout(const Duration(minutes: 10));

        print('WHISPER_ARABIC_LANGUAGE: ${result.language}');
        print('WHISPER_ARABIC_TRANSCRIPT: ${result.text}');
        expect(result.text.trim(), isNotEmpty);
        expect(result.language, 'ar');
        expect(
          RegExp(r'[\u0600-\u06FF]').hasMatch(result.text),
          isTrue,
          reason: 'The Arabic WAV must produce Arabic-script text, not merely a loaded native library.',
        );
      } finally {
        if (await wav.exists()) await wav.delete();
        await speech.dispose();
      }
    },
  );
}
