import 'dart:async';

/// A single tool invocation has an identity independent of its parent request
/// and planner step. Cancellation is scoped to this invocation.
class ToolCallCancellation {
  ToolCallCancellation({
    required this.toolCallId,
    required this.requestId,
    required this.toolName,
  });

  final String toolCallId;
  final String requestId;
  final String toolName;
  final Completer<void> _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  bool cancel() {
    if (_cancelled.isCompleted) return false;
    _cancelled.complete();
    return true;
  }

  void throwIfCancelled() {
    if (isCancelled) throw ToolCallInterrupted(toolCallId);
  }
}

class ToolCallInterrupted implements Exception {
  const ToolCallInterrupted(this.toolCallId);
  final String toolCallId;
  @override
  String toString() => 'Tool call $toolCallId was interrupted.';
}

class ToolCallRegistry {
  final Map<String, ToolCallCancellation> _active = <String, ToolCallCancellation>{};

  ToolCallCancellation begin({
    required String toolCallId,
    required String requestId,
    required String toolName,
  }) {
    if (_active.containsKey(toolCallId)) {
      throw StateError('Duplicate active tool_call_id: $toolCallId');
    }
    final call = ToolCallCancellation(
      toolCallId: toolCallId,
      requestId: requestId,
      toolName: toolName,
    );
    _active[toolCallId] = call;
    return call;
  }

  bool cancel(String toolCallId) => _active[toolCallId]?.cancel() ?? false;
  ToolCallCancellation? get(String toolCallId) => _active[toolCallId];
  void finish(String toolCallId) => _active.remove(toolCallId);
  int get activeCount => _active.length;
}
