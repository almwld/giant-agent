import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:giant_agent_x/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cold launch renders Flutter UI and Gain PTY executes a shell command',
      (tester) async {
    await app.main();
    await tester.pump();

    // A visible Flutter frame must be rendered before asynchronous startup
    // services finish; this guards against returning to a black launch window.
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsWidgets);
    expect(tester.takeException(), isNull);

    const method = MethodChannel('giant_agent/pty');
    const events = EventChannel('giant_agent/pty/events');
    const marker = 'GAIN_PTY_EMULATOR_SMOKE_OK';
    final output = StringBuffer();
    final observed = Completer<void>();
    StreamSubscription<dynamic>? subscription;
    int? handle;

    try {
      subscription = events.receiveBroadcastStream().listen((dynamic event) {
        if (event is! Map) return;
        final data = event['data'];
        if (data is Uint8List) {
          output.write(utf8.decode(data, allowMalformed: true));
        } else if (data is List<int>) {
          output.write(utf8.decode(data, allowMalformed: true));
        }
        if (!observed.isCompleted && output.toString().contains(marker)) {
          observed.complete();
        }
      });

      final available = await method
          .invokeMethod<bool>('available')
          .timeout(const Duration(seconds: 5));
      expect(available, isTrue, reason: '/dev/ptmx and the Gain JNI library must be available.');

      handle = await method.invokeMethod<int>(
        'start',
        <String, Object>{
          'rows': 24,
          'cols': 80,
          'shell': '/system/bin/sh',
        },
      ).timeout(const Duration(seconds: 8));
      expect(handle, isNotNull);
      expect(handle, greaterThan(0));

      final command = 'echo $marker\\n';
      final bytes = Uint8List.fromList(utf8.encode(command));
      final written = await method.invokeMethod<int>(
        'write',
        <String, Object>{
          'handle': handle!,
          'input': bytes,
        },
      ).timeout(const Duration(seconds: 5));
      expect(written, bytes.length);

      await observed.future.timeout(const Duration(seconds: 8));
      expect(output.toString(), contains(marker));
    } finally {
      if (handle != null) {
        await method.invokeMethod<void>(
          'stop',
          <String, Object>{'handle': handle},
        );
      }
      await subscription?.cancel();
    }
  });
}
