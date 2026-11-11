import 'dart:async';

import '../agent/architecture/agent_event_bus.dart';

/// Bridges a model's ask-user tool call to the active chat UI without exposing
/// internal reasoning or allowing a worker to silently invent user approval.
class AgentUserInputBroker {
  AgentUserInputBroker._();
  static final AgentUserInputBroker instance = AgentUserInputBroker._();

  final Map<String, Completer<String?>> _pending = <String, Completer<String?>>{};

  Future<String?> askUser({
    required String requestId,
    required String taskId,
    required String sessionId,
    required String question,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final prompt = question.trim();
    if (requestId.isEmpty || taskId.isEmpty || sessionId.isEmpty ||
        prompt.isEmpty || prompt.length > 2000) {
      throw ArgumentError('ask_user requires request, task, session and a question of 1–2000 characters.');
    }
    if (timeout <= Duration.zero || timeout > const Duration(minutes: 3)) {
      throw ArgumentError('User-input timeout must be between 1 second and 3 minutes.');
    }
    final id = 'user_input_${requestId}_${taskId}_${DateTime.now().microsecondsSinceEpoch}';
    final completer = Completer<String?>();
    _pending[id] = completer;
    AgentEventBus.instance.publish(<String, Object?>{
      'id': id,
      'input_request_id': id,
      'request_id': requestId,
      'task_id': taskId,
      'session_id': sessionId,
      'type': 'user_input_requested',
      'title': 'يحتاج الوكيل إلى إجابتك',
      'question': prompt,
      'status': 'pending',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      AgentEventBus.instance.publish(<String, Object?>{
        'id': '${id}_timeout',
        'input_request_id': id,
        'request_id': requestId,
        'task_id': taskId,
        'session_id': sessionId,
        'type': 'user_input_timed_out',
        'title': 'انتهت مهلة انتظار إجابتك',
        'status': 'interrupted',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });
      return null;
    } finally {
      _pending.remove(id);
    }
  }

  bool submitAnswer(String inputRequestId, String? answer) {
    final completer = _pending[inputRequestId];
    if (completer == null || completer.isCompleted) return false;
    final normalized = answer?.trim();
    completer.complete(normalized == null || normalized.isEmpty ? null : normalized);
    AgentEventBus.instance.publish(<String, Object?>{
      'id': '${inputRequestId}_answered',
      'input_request_id': inputRequestId,
      'type': 'user_input_answered',
      'title': normalized == null || normalized.isEmpty
          ? 'تم إلغاء سؤال الوكيل'
          : 'وصلت إجابتك إلى الوكيل',
      'status': normalized == null || normalized.isEmpty ? 'cancelled' : 'completed',
      'answer': normalized,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });
    return true;
  }

  int get pendingCount => _pending.length;
}
