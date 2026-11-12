import 'dart:async';
import 'dart:math';

import '../domain/terminal/gain_pty_client.dart';
import '../domain/terminal/gain_command_output_parser.dart';

class GainCommandResult {
  const GainCommandResult({
    required this.command,
    required this.output,
    required this.exitCode,
    required this.duration,
    this.timedOut = false,
    this.sessionLost = false,
  });

  final String command;
  final String output;
  final int exitCode;
  final Duration duration;
  final bool timedOut;
  final bool sessionLost;

  bool get succeeded => exitCode == 0 && !timedOut && !sessionLost;
}

/// Command-level adapter over Gain's persistent native PTY.
/// Keep this tool out of model-visible registries until ApprovalManager binds
/// approval to the exact command and execution policy.
class GainTerminalTool {
  GainTerminalTool({GainPtyClient? client})
      : _client = client ?? GainPtyClient();

  final GainPtyClient _client;
  Future<void> _tail = Future<void>.value();
  int _sequence = 0;
  final Random _random = Random.secure();

  Future<GainCommandResult> execute(
    String command, {
    Duration timeout = const Duration(seconds: 60),
  }) {
    final completer = Completer<GainCommandResult>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await _executeSerialized(
          command,
          timeout: timeout,
        ));
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Future<GainCommandResult> _executeSerialized(
    String command, {
    required Duration timeout,
  }) async {
    final normalized = command.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(command, 'command', 'Command cannot be empty.');
    }
    if (normalized.length > 16000) {
      throw ArgumentError.value(command, 'command', 'Command exceeds 16 KB.');
    }

    final effectiveTimeout = Duration(
      seconds: timeout.inSeconds.clamp(1, 900).toInt(),
    );
    final startedAt = DateTime.now();
    final nonce = List<String>.generate(
      4,
      (_) => _random.nextInt(0x7fffffff).toRadixString(16),
    ).join();
    final token = '${nonce}_${++_sequence}';
    final marker = '__GAIN_DONE_${token}_';
    final parser = GainCommandOutputParser(marker: marker);
    final completed = Completer<int>();
    final sessionLost = Completer<void>();
    StreamSubscription<String>? outputSubscription;
    StreamSubscription<void>? closedSubscription;

    // Attach listeners before starting/writing, so no early output is lost.
    outputSubscription = _client.output.listen((chunk) {
      parser.add(chunk);
      if (!completed.isCompleted && parser.exitCode != null) {
        completed.complete(parser.exitCode!);
      }
    }, onError: (Object error, StackTrace stack) {
      if (!sessionLost.isCompleted) sessionLost.complete();
    });
    closedSubscription = _client.onSessionClosed.listen((_) {
      if (!completed.isCompleted && !sessionLost.isCompleted) {
        sessionLost.complete();
      }
    });

    try {
      final started = await _client.start();
      if (!started) {
        return GainCommandResult(
          command: normalized,
          output: 'Gain native PTY could not start /system/bin/sh.',
          exitCode: 126,
          duration: DateTime.now().difference(startedAt),
          sessionLost: true,
        );
      }

      // Capture the exit status immediately after the submitted command.
      // The marker includes a unique execution token and may span stream chunks.
      final script =
          '$normalized\n__gain_status=\$?; printf \'\\n$marker%s__\\n\' "\$__gain_status"\n';
      await _client.write(script);

      final exitCode = await Future.any<int>([
        completed.future,
        sessionLost.future.then((_) => -1),
      ]).timeout(effectiveTimeout);

      final output = parser.output;
      final lost = exitCode < 0;
      return GainCommandResult(
        command: normalized,
        output: output,
        exitCode: lost ? 126 : exitCode,
        duration: DateTime.now().difference(startedAt),
        sessionLost: lost,
      );
    } on TimeoutException {
      try {
        await _client.interrupt();
        // Give SIGINT a short grace window. If the command does not return
        // its sentinel, stop the PTY before admitting the next queued command.
        await Future.any<void>([
          completed.future.then((_) {}),
          sessionLost.future,
        ]).timeout(const Duration(milliseconds: 750));
      } catch (_) {
        await _client.stop();
      }
      return GainCommandResult(
        command: normalized,
        output: parser.output,
        exitCode: 124,
        duration: DateTime.now().difference(startedAt),
        timedOut: true,
      );
    } finally {
      await outputSubscription.cancel();
      await closedSubscription.cancel();
    }
  }

  Future<void> dispose() => _client.dispose();
}
