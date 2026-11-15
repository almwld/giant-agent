import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/tools/gain_terminal_tool.dart';
import 'package:giant_agent_x/tools/terminal_tool_coordinator.dart';

void main() {
  group('TerminalToolCoordinator', () {
    test('executes only after approving the exact command and emits timeline events', () async {
      const command = 'pwd && ls';
      final events = <Map<String, dynamic>>[];
      var executed = false;
      String? approvedCommand;
      final coordinator = TerminalToolCoordinator(
        requestApproval: (value) async { approvedCommand = value; return true; },
        execute: (value, timeout) async {
          executed = true;
          expect(value, command);
          expect(timeout, const Duration(seconds: 30));
          return const GainCommandResult(command: command, output: '/data/user/0/app/files', exitCode: 0, duration: Duration(milliseconds: 12));
        },
        onEvent: events.add,
      );
      final result = await coordinator.execute(command: command, timeoutSeconds: 30);
      expect(approvedCommand, command);
      expect(executed, isTrue);
      expect(result['ok'], isTrue);
      expect(result['exit_code'], 0);
      expect(events.map((event) => event['type']), ['approval_requested', 'tool_start', 'tool_output']);
      expect(events.first['command'], command);
    });

    test('does not execute when approval is denied', () async {
      var executed = false;
      final events = <Map<String, dynamic>>[];
      final coordinator = TerminalToolCoordinator(
        requestApproval: (_) async => false,
        execute: (_, __) async { executed = true; throw StateError('must not execute'); },
        onEvent: events.add,
      );
      final result = await coordinator.execute(command: 'id');
      expect(executed, isFalse);
      expect(result['ok'], isFalse);
      expect(result['denied'], isTrue);
      expect(events.map((event) => event['type']), ['approval_requested', 'approval_denied']);
    });

    test('does not request approval or execute when already cancelled', () async {
      var requested = false;
      var executed = false;
      final coordinator = TerminalToolCoordinator(
        requestApproval: (_) async { requested = true; return true; },
        execute: (_, __) async {
          executed = true;
          throw StateError('must not execute');
        },
      );

      final result = await coordinator.execute(
        command: 'id',
        isCancelled: () => true,
      );

      expect(requested, isFalse);
      expect(executed, isFalse);
      expect(result['cancelled'], isTrue);
    });

    test('does not execute when cancellation occurs while approval is pending', () async {
      final approval = Completer<bool>();
      var cancelled = false;
      var executed = false;
      final coordinator = TerminalToolCoordinator(
        requestApproval: (_) => approval.future,
        execute: (_, __) async {
          executed = true;
          throw StateError('must not execute');
        },
      );

      final pending = coordinator.execute(
        command: 'id',
        isCancelled: () => cancelled,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      cancelled = true;
      final result = await pending;
      approval.complete(true);

      expect(executed, isFalse);
      expect(result['cancelled'], isTrue);
    });

    test('passes cancellation through to the cancellable executor', () async {
      var cancelled = false;
      var receivedCancellationCallback = false;
      final events = <Map<String, dynamic>>[];
      final coordinator = TerminalToolCoordinator(
        requestApproval: (_) async => true,
        execute: (_, __) async => throw StateError('legacy executor must not be used'),
        executeCancellable: (command, timeout, isCancelled) async {
          receivedCancellationCallback = isCancelled != null;
          cancelled = true;
          expect(isCancelled?.call(), isTrue);
          return GainCommandResult(
            command: command,
            output: 'interrupted',
            exitCode: 130,
            duration: Duration.zero,
            cancelled: true,
          );
        },
        onEvent: events.add,
      );

      final result = await coordinator.execute(
        command: 'sleep 30',
        isCancelled: () => cancelled,
      );

      expect(receivedCancellationCallback, isTrue);
      expect(result['ok'], isFalse);
      expect(result['cancelled'], isTrue);
      expect(events.last['type'], 'tool_interrupted');
    });

    test('rejects empty and oversized commands before requesting approval', () async {
      var requested = false;
      final coordinator = TerminalToolCoordinator(
        requestApproval: (_) async { requested = true; return true; },
        execute: (_, __) async => throw StateError('must not execute'),
      );
      await expectLater(coordinator.execute(command: '  '), throwsArgumentError);
      await expectLater(coordinator.execute(command: List.filled(2001, 'x').join()), throwsArgumentError);
      expect(requested, isFalse);
    });

    test('reports non-zero exit codes as failed results', () async {
      final coordinator = TerminalToolCoordinator(
        requestApproval: (_) async => true,
        execute: (_, __) async => const GainCommandResult(command: 'false', output: '', exitCode: 1, duration: Duration(milliseconds: 3)),
      );
      final result = await coordinator.execute(command: 'false');
      expect(result['ok'], isFalse);
      expect(result['exit_code'], 1);
    });
  });
}
