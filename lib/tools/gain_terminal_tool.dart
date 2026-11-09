import 'dart:async';

import '../domain/terminal/gain_pty_client.dart';

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
      seconds: timeout.inSeconds.clamp(1, 900),
    );
    final startedAt = DateTime.now();
    final token =
        '${DateTime.now().microsecondsSinceEpoch}_${++_sequence}';
    final marker = '__GAIN_DONE_${token}_';
    final matcher = RegExp('${RegExp.escape(marker)}(-?\\d+)__');
    final buffer = StringBuffer();
    final completed = Completer<int>();
    final sessionLost = Completer<void>();
    StreamSubscription<String>? outputSubscription;
    StreamSubscription<void>? closedSubscription;

    // Attach listeners before starting/writing, so no early output is lost.
    outputSubscription = _client.output.listen((chunk) {
      if (buffer.length < 1024 * 1024) {
        final remaining = 1024 * 1024 - buffer.length;
        buffer.write(chunk.length <= remaining ? chunk : chunk.substring(0, remaining));
      }
      if (!completed.isCompleted) {
        final match = matcher.firstMatch(buffer.toString());
        if (match != null) {
          completed.complete(int.tryParse(match.group(1) ?? '') ?? 126);
        }
      }
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
          '$normalized\n__gain_status=\$?; printf \'\\n${marker}%s__\\n\' "\$__gain_status"\n';
      await _client.write(script);

      final exitCode = await Future.any<int>([
        completed.future,
        sessionLost.future.then((_) => -1),
      ]).timeout(effectiveTimeout);

      final raw = buffer.toString();
      final match = matcher.firstMatch(raw);
      final output = match == null ? raw : raw.substring(0, match.start);
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
      } catch (_) {}
      return GainCommandResult(
        command: normalized,
        output: buffer.toString(),
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
