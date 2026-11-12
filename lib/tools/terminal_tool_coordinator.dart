import 'dart:math';

import 'gain_terminal_tool.dart';

typedef TerminalApprovalRequest = Future<bool> Function(String command);
typedef TerminalCommandExecution = Future<GainCommandResult> Function(String command, Duration timeout);

class TerminalToolCoordinator {
  TerminalToolCoordinator({required TerminalApprovalRequest requestApproval, required TerminalCommandExecution execute, void Function(Map<String, dynamic>)? onEvent})
      : _requestApproval = requestApproval, _execute = execute, _onEvent = onEvent;

  final TerminalApprovalRequest _requestApproval;
  final TerminalCommandExecution _execute;
  final void Function(Map<String, dynamic>)? _onEvent;
  final Random _random = Random.secure();

  String _eventId(String phase) => 'gain_${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 20)}_$phase';

  void _emit(String phase, String title, String status, {String? command, String? output, String? details}) {
    _onEvent?.call(<String, dynamic>{
      'id': _eventId(phase), 'type': phase, 'tool_name': 'gain_terminal',
      'title': title, 'status': status,
      if (command != null) 'command': command,
      if (output != null) 'output': output,
      if (details != null) 'details': details,
    });
  }

  Future<Map<String, dynamic>> execute({required String command, int timeoutSeconds = 60}) async {
    final normalized = command.trim();
    if (normalized.isEmpty || normalized.length > 2000 || normalized.contains('\u0000')) {
      throw ArgumentError.value(command, 'command', 'Command must be 1..2000 characters and contain no NUL byte.');
    }
    final timeout = Duration(seconds: timeoutSeconds.clamp(1, 900).toInt());
    _emit('approval_requested', 'موافقة مطلوبة لتنفيذ أمر طرفية', 'running', command: normalized);
    final approved = await _requestApproval(normalized);
    if (!approved) {
      _emit('approval_denied', 'رفض المستخدم تنفيذ أمر الطرفية', 'failed', command: normalized);
      return <String, dynamic>{'ok': false, 'denied': true, 'command': normalized, 'error': 'User denied execution. The command was not run.'};
    }
    _emit('tool_start', 'بدء تنفيذ أمر Gain Terminal', 'running', command: normalized);
    try {
      final result = await _execute(normalized, timeout);
      final ok = result.succeeded;
      final output = result.output.length > 12000 ? '${result.output.substring(0, 12000)}\n[output truncated]' : result.output;
      _emit(ok ? 'tool_output' : 'tool_error', ok ? 'اكتمل تنفيذ أمر الطرفية' : 'انتهى أمر الطرفية بحالة غير ناجحة', ok ? 'completed' : 'failed', command: normalized, output: output, details: 'exit_code=${result.exitCode}; timed_out=${result.timedOut}; session_lost=${result.sessionLost}');
      return <String, dynamic>{'ok': ok, 'command': normalized, 'output': output, 'exit_code': result.exitCode, 'timed_out': result.timedOut, 'session_lost': result.sessionLost, 'duration_ms': result.duration.inMilliseconds};
    } catch (error) {
      _emit('tool_error', 'فشل تنفيذ أمر الطرفية', 'failed', command: normalized, details: error.toString());
      return <String, dynamic>{'ok': false, 'command': normalized, 'error': error.toString()};
    }
  }
}