import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:giant_agent_x/main.dart' as app;
import 'package:giant_agent_x/services/local_arabic_tts_service.dart';
import 'package:giant_agent_x/services/local_speech_recognition_service.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('physical-device Arabic voice acceptance: ASR, TTS, latency and RSS',
      (tester) async {
    await app.main();
    await tester.pump();

    final rssBefore = ProcessInfo.currentRss;
    final asr = LocalSpeechRecognitionService.instance;
    final asrWatch = Stopwatch()..start();
    await asr.initialize().timeout(const Duration(minutes: 10));
    final fixture = await rootBundle.load('integration_test/fixtures/arabic_smoke.wav');
    final directory = await getTemporaryDirectory();
    final wav = File('${directory.path}/device-arabic-acceptance.wav');
    await wav.writeAsBytes(fixture.buffer.asUint8List(
      fixture.offsetInBytes, fixture.lengthInBytes,
    ), flush: true);
    final transcript = await asr.transcribeFile(wav.path, threads: 2)
        .timeout(const Duration(minutes: 10));
    asrWatch.stop();
    expect(transcript.language, 'ar');
    expect(RegExp(r'[\u0600-\u06FF]').hasMatch(transcript.text), isTrue);

    final tts = LocalArabicTtsService.instance;
    if (!await tts.isInstalled()) {
      await tts.install().timeout(const Duration(minutes: 15));
    }
    final ttsWatch = Stopwatch()..start();
    await tts.initialize().timeout(const Duration(minutes: 2));
    await tts.speak('اختبار قبول الصوت العربي على الهاتف الحقيقي.')
        .timeout(const Duration(minutes: 4));
    ttsWatch.stop();

    final rssAfterTts = ProcessInfo.currentRss;
    print('DEVICE_VOICE_ACCEPTANCE: ${{
      'device': Platform.operatingSystem,
      'asr_ms': asrWatch.elapsedMilliseconds,
      'tts_ms': ttsWatch.elapsedMilliseconds,
      'rss_before_bytes': rssBefore,
      'rss_after_tts_bytes': rssAfterTts,
      'rss_delta_bytes': rssAfterTts - rssBefore,
      'language': transcript.language,
      'transcript': transcript.text,
    }}');
    await wav.delete();
    await asr.dispose();
    await tts.dispose();
  });
}
