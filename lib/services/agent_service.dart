import '../agent/architecture/agent_kernel.dart' as execution;
import '../agent/architecture/agent_timeline_event.dart';
import '../agent/architecture/agent_event_bus.dart';
import '../domain/kernel/agent_kernel.dart' as durable;
import '../domain/kernel/agent_kernel_store.dart';
import 'model_service.dart';

/// The sole application-facing task boundary.
///
/// Durable admission, FIFO execution and request results are owned by the
/// SQLite kernel. The existing execution kernel remains the executor and
/// continues to own the shared ModelService/LlamaService, planner, tools,
/// cancellation and approval behavior.
class AgentService {
  AgentService._()
      : _executionKernel = execution.AgentKernel.instance,
        _models = ModelService(),
        _store = AgentKernelStore(),
        _initializeExecutionRuntime = true {
    _durableKernel = durable.AgentKernel(
      store: _store,
      executor: _executeWithSharedRuntime,
    );
  }

  /// Injectable seam for contract tests. Production callers use [instance].
  AgentService.withExecutor({
    required durable.KernelRequestExecutor executor,
    required AgentKernelStore store,
  })  : _executionKernel = execution.AgentKernel.instance,
        _models = ModelService(),
        _store = store,
        _initializeExecutionRuntime = false {
    _durableKernel = durable.AgentKernel(store: store, executor: executor);
  }

  static final AgentService instance = AgentService._();

  final execution.AgentKernel _executionKernel;
  final ModelService _models;
  late final durable.AgentKernel _durableKernel;
  final AgentKernelStore _store;
  final bool _initializeExecutionRuntime;
  StreamSubscription<Map<String, dynamic>>? _eventSubscription;
  Future<void> _journalTail = Future<void>.value();
  Future<void>? _initialization;
  bool _initialized = false;
  static int _requestSequence = 0;

  static Future<String> _executeWithSharedRuntime(
    KernelRequestRecord request,
  ) async {
    late final execution.AgentResponse response;
    try {
      response = await execution.AgentKernel.instance.execute(
        execution.AgentRequest(
          id: request.id,
          prompt: request.prompt,
          conversationId: request.conversationId,
        ),
      );
    } finally {
      await instance._flushExecutionJournal();
    }
    final output = response.output;
    if (_isInterruptedOutput(output)) {
      throw durable.KernelRequestInterrupted(output);
    }
    return output;
  }

  static bool _isInterruptedOutput(String output) =>
      output.startsWith('تم إيقاف المهمة') ||
      output.startsWith('تم إيقاف تنفيذ الوكيل') ||
      output.startsWith('تم إيقاف الوكيل بعد اكتمال الأداة') ||
      output.startsWith('تم إيقاف التوليد') ||
      output.startsWith('وصل الوكيل إلى الحد الآمن') ||
      output.startsWith('أوقف الوكيل تكرار استدعاء الأداة') ||
      output.contains('[تم إيقاف التوليد]');

  bool get isRunning => _executionKernel.isExecuting;

  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    final active = _initialization;
    if (active != null) return active;

    late final Future<void> shared;
    shared = _initialize().whenComplete(() {
      if (identical(_initialization, shared)) _initialization = null;
    });
    _initialization = shared;
    return shared;
  }

  void _attachExecutionJournal() {
    _eventSubscription ??= AgentEventBus.instance.events.listen((event) {
      _journalTail = _journalTail
          .then((_) => _store.appendRequestEvent(event))
          .catchError((Object _) {
        // Request completion remains owned by the durable kernel. A failed
        // supplemental timeline write must not corrupt the shared runtime.
      });
    });
  }

  Future<void> _flushExecutionJournal() => _journalTail;

  Future<void> _initialize() async {
    // The execution runtime must be ready before queued durable work is drained.
    if (_initializeExecutionRuntime) await _executionKernel.initialize();
    _attachExecutionJournal();
    await _durableKernel.initialize();
    _initialized = true;
  }

  Future<String> runTask(
    String prompt, {
    String conversationId = 'global',
    String? requestId,
  }) async {
    await initialize();
    final suppliedRequestId = requestId?.trim();
    final resolvedRequestId =
        suppliedRequestId == null || suppliedRequestId.isEmpty
            ? '${DateTime.now().microsecondsSinceEpoch}_${++_requestSequence}'
            : suppliedRequestId;
    final record = await _durableKernel.submit(
      id: resolvedRequestId,
      prompt: prompt,
      conversationId: conversationId,
    );
    if (record.status == 'failed') {
      throw StateError(record.error ?? 'Agent request failed.');
    }
    if (record.status != 'completed' && record.status != 'interrupted') {
      throw StateError('Unexpected durable request state: ${record.status}');
    }
    return record.result ?? '';
  }

  Future<KernelRequestRecord?> request(String requestId) =>
      _durableKernel.request(requestId);

  Future<List<KernelEventRecord>> eventsFor(String requestId) =>
      _durableKernel.eventsFor(requestId);

  Future<bool> cancel() => _executionKernel.cancel();

  Future<Map<String, dynamic>> exportWorkspace() =>
      _executionKernel.exportWorkspace();

  Future<List<String>> listWorkspaceFiles() =>
      _executionKernel.listWorkspaceFiles();

  /// Exposes the same process-wide model facade used by the executor.
  ModelService get modelService => _models;

  /// Live execution metadata remains sourced from the existing runtime.
  /// Durable history can be replayed with [eventsFor].
  Stream<AgentTimelineEvent> get events => _executionKernel.events;

  /// Closes the injected durable store in contract tests. The app singleton
  /// should remain alive for the process lifetime.
  Future<void> disposeForTesting() => _durableKernel.dispose();
}
