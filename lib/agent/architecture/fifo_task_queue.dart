import 'dart:async';
import 'dart:collection';

class _QueuedOperation<T> {
  _QueuedOperation(this.operation);

  final Future<T> Function() operation;
  final Completer<T> completer = Completer<T>();
}

/// A small FIFO executor shared by the agent kernel and unit tests.
class FifoTaskQueue {
  final Queue<_QueuedOperation<dynamic>> _queue =
      Queue<_QueuedOperation<dynamic>>();
  bool _running = false;

  bool get isRunning => _running;
  int get pendingCount => _queue.length;

  Future<T> enqueue<T>(Future<T> Function() operation) {
    final item = _QueuedOperation<T>(operation);
    _queue.addLast(item);
    if (!_running) {
      _running = true;
      unawaited(_drain());
    }
    return item.completer.future;
  }

  Future<void> _drain() async {
    try {
      while (_queue.isNotEmpty) {
        final item = _queue.removeFirst();
        try {
          final result = await item.operation();
          if (!item.completer.isCompleted) item.completer.complete(result);
        } catch (error, stackTrace) {
          if (!item.completer.isCompleted) {
            item.completer.completeError(error, stackTrace);
          }
        }
      }
    } finally {
      _running = false;
      if (_queue.isNotEmpty) {
        _running = true;
        unawaited(_drain());
      }
    }
  }
}
