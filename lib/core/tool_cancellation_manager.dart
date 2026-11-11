import 'dart:async';

class ToolCancelledException implements Exception {
  const ToolCancelledException(this.toolCallId, [this.reason = 'Tool cancelled']);
  final String toolCallId;
  final String reason;
  @override
  String toString() => 'ToolCancelledException($toolCallId): $reason';
}

/// Cooperative cancellation token. Cancelling a token does not forcibly stop
/// arbitrary Dart code; the operation must check the token or await token-aware
/// primitives, and native/network work must receive its own abort signal.
class ToolCancellationToken {
  ToolCancellationToken(this.toolCallId);
  final String toolCallId;
  final Completer<String> _cancelled = Completer<String>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<String> get whenCancelled => _cancelled.future;

  void cancel([String reason = 'Cancelled by user']) {
    if (!_cancelled.isCompleted) _cancelled.complete(reason);
  }

  void throwIfCancelled() {
    if (isCancelled) {
      throw ToolCancelledException(toolCallId, _cancelledReason);
    }
  }

  String get _cancelledReason =>
      _cancelled.isCompleted ? 'Cancelled by user or parent task' : 'Cancelled';

  Future<void> delay(Duration duration) async {
    throwIfCancelled();
    final result = await Future.any<Object>([
      Future<void>.delayed(duration).then<Object>((_) => true),
      whenCancelled.then<Object>((reason) => ToolCancelledException(toolCallId, reason)),
    ]);
    if (result is ToolCancelledException) throw result;
    throwIfCancelled();
  }

  /// Stops waiting immediately on cancellation. The underlying operation is
  /// still required to observe this token to stop its actual work.
  Future<T> race<T>(Future<T> operation) {
    throwIfCancelled();
    return Future.any<T>([
      operation,
      whenCancelled.then<T>((reason) => throw ToolCancelledException(toolCallId, reason)),
    ]);
  }
}

class ToolCancellationManager {
  final Map<String, ToolCancellationToken> _tokens = {};
  bool _disposed = false;

  ToolCancellationToken registerTool(String toolCallId) {
    _ensureAlive();
    if (toolCallId.isEmpty) throw ArgumentError.value(toolCallId, 'toolCallId');
    final existing = _tokens[toolCallId];
    if (existing != null && !existing.isCancelled) {
      throw StateError('A live cancellation token already exists for $toolCallId');
    }
    final token = ToolCancellationToken(toolCallId);
    _tokens[toolCallId] = token;
    return token;
  }

  ToolCancellationToken? tokenFor(String toolCallId) => _tokens[toolCallId];

  bool isCancelled(String toolCallId) =>
      _tokens[toolCallId]?.isCancelled ?? false;

  Future<bool> cancelTool(
    String toolCallId, {
    String reason = 'Cancelled by user',
  }) async {
    final token = _tokens[toolCallId];
    if (token == null || token.isCancelled) return false;
    token.cancel(reason);
    return true;
  }

  void unregisterTool(String toolCallId, {ToolCancellationToken? expected}) {
    final current = _tokens[toolCallId];
    if (current == null) return;
    if (expected != null && !identical(current, expected)) return;
    _tokens.remove(toolCallId);
  }

  Future<void> cancelAll([String reason = 'Parent task cancelled']) async {
    for (final token in _tokens.values.toList()) {
      token.cancel(reason);
    }
  }

  void _ensureAlive() {
    if (_disposed) throw StateError('ToolCancellationManager is disposed');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await cancelAll('Cancellation manager disposed');
    _tokens.clear();
  }
}
