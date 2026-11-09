import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/domain/terminal/gain_pty_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannel methodChannel;
  late StreamController<dynamic> events;
  late GainPtyClient client;
  late List<List<int>> writes;

  setUp(() {
    methodChannel = const MethodChannel('test/giant_agent/pty');
    events = StreamController<dynamic>.broadcast();
    writes = <List<int>>[];
  });

  tearDown(() async {
    await client.dispose();
    await events.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });

  test('retries only the unsent suffix after a partial PTY write', () async {
    var writeCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
      switch (call.method) {
        case 'available':
          return true;
        case 'start':
          return 41;
        case 'write':
          final input = call.arguments['input'] as Uint8List;
          writes.add(List<int>.from(input));
          writeCount++;
          return writeCount == 1 ? 2 : input.length;
        case 'stop':
          return null;
        default:
          throw MissingPluginException('Unexpected method: ${call.method}');
      }
    });

    client = GainPtyClient(
      methodChannel: methodChannel,
      eventStream: events.stream,
    );
    expect(await client.start(), isTrue);
    await client.writeBytes(Uint8List.fromList([10, 20, 30, 40, 50]));

    expect(writes, [
      [10, 20, 30, 40, 50],
      [30, 40, 50],
    ]);
  });

  test('fails after bounded partial writes without replaying accepted bytes',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
      switch (call.method) {
        case 'available':
          return true;
        case 'start':
          return 42;
        case 'write':
          final input = call.arguments['input'] as Uint8List;
          writes.add(List<int>.from(input));
          return 1;
        case 'stop':
          return null;
        default:
          throw MissingPluginException('Unexpected method: ${call.method}');
      }
    });

    client = GainPtyClient(
      methodChannel: methodChannel,
      eventStream: events.stream,
    );
    expect(await client.start(), isTrue);
    await expectLater(
      client.writeBytes(Uint8List.fromList([1, 2, 3, 4])),
      throwsA(isA<StateError>()),
    );

    expect(writes, [
      [1, 2, 3, 4],
      [2, 3, 4],
      [3, 4],
    ]);
  });
}
