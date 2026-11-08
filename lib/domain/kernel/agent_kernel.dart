import 'dart:async';

import 'agent_kernel_store.dart';

typedef KernelRequestExecutor = Future<String> Function(
  KernelRequestRecord request,
);

class AgentKernel {
  AgentKernel({
    required AgentKernelStore store,
    required KernelRequestExecutor executor,
  })  : _store = store,
        _executor = executor;

  final AgentKernelStore _store;
  final KernelRequestExecutor _executor;
  final Map<String, Completer<KernelRequestRecord>> _waiters = {};
  Future<void>? _pumpFuture;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    await _store.reconcileAfterProcessRestart();
    _initialized = true;
    _schedulePump();
  }

  /// Persists admission before returning. FIFO order is assigned transactionally
  /// by SQLite, so concurrent callers cannot choose their own queue positions.
  Future<KernelRequestRecord> submit({
    required String id,
    required String prompt,
    String conversationId = 'default',
  }) async {
    if (!_initialized) await initialize();
    final normalized = prompt.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(prompt, 'prompt', 'Request cannot be empty.');
    }
    if (_waiters.containsKey(id) || await _store.getRequest(id) != null) {
      throw StateError('Duplicate request id: $id');
    }

    final waiter = Completer<KernelRequestRecord>();
    _waiters[id] = waiter;
    try {
      await _store.enqueue(
        id: id,
        prompt: normalized,
        conversationId: conversationId,
      );
      _schedulePump();
      return await waiter.future;
    } catch (_) {
      _waiters.remove(id);
      rethrow;
    }
  }

  Future<void> _schedulePump() {
    final active = _pumpFuture;
    if (active != null) return active;
    late final Future<void> run;
    run = _pump().whenComplete(() {
      if (identical(_pumpFuture, run)) _pumpFuture = null;
    });
    _pumpFuture = run;
    return run;
  }

  Future<void> _pump() async {
    while (true) {
      final queued = await _store.queuedRequests();
      if (queued.isEmpty) return;
      final request = queued.first;
      try {
        await _store.markRunning(request.id);
        final running = await _store.getRequest(request.id);
        if (running == null) throw StateError('Queued request disappeared.');
        final result = await _executor(running);
        await _store.complete(request.id, result);
      } catch (error) {
        try {
          await _store.fail(request.id, error);
        } catch (_) {
          // A persistence failure must not be disguised as a successful result.
        }
      } finally {
        final completed = await _store.getRequest(request.id);
        final waiter = _waiters.remove(request.id);
        if (waiter != null && !waiter.isCompleted) {
          if (completed == null) {
            waiter.completeError(StateError('Request could not be reloaded.'));
          } else {
            waiter.complete(completed);
          }
        }
      }
    }
  }

  Future<KernelRequestRecord?> request(String id) => _store.getRequest(id);

  Future<List<KernelEventRecord>> eventsFor(String requestId) =>
      _store.eventsFor(requestId);

  Future<void> dispose() async {
    await _pumpFuture;
    await _store.close();
    _initialized = false;
  }
}
