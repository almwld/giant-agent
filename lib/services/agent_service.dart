import '../agent/architecture/agent_kernel.dart' as execution;
import '../agent/architecture/agent_timeline_event.dart';
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
        _durableKernel = durable.AgentKernel(
          store: AgentKernelStore(),
          executor: _executeWithSharedRuntime,
        ),
        _initializeExecutionRuntime = true;

  /// Injectable seam for contract tests. Production callers use [instance].
  AgentService.withExecutor({
    required durable.KernelRequestExecutor executor,
    required AgentKernelStore store,
  })  : _executionKernel = execution.AgentKernel.instance,
        _models = ModelService(),
        _durableKernel = durable.AgentKernel(store: store, executor: executor),
        _initializeExecutionRuntime = false;

  static final AgentService instance = AgentService._();

  final execution.AgentKernel _executionKernel;
  final ModelService _models;
  final durable.AgentKernel _durableKernel;
  final bool _initializeExecutionRuntime;
  Future<void>? _initialization;
  bool _initialized = false;
  static int _requestSequence = 0;

  static Future<String> _executeWithSharedRuntime(
    KernelRequestRecord request,
  ) async {
    final response = await execution.AgentKernel.instance.execute(
      execution.AgentRequest(
        id: request.id,
        prompt: request.prompt,
        conversationId: request.conversationId,
      ),
    );
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

  Future<void> _initialize() async {
    // The execution runtime must be ready before queued durable work is drained.
    if (_initializeExecutionRuntime) await _executionKernel.initialize();
    await _durableKernel.initialize();
    _initialized = true;
  }

  Future<String> runTask(
    String prompt, {
    String conversationId = 'global',
  }) async {
    await initialize();
    final requestId = '${DateTime.now().microsecondsSinceEpoch}_${++_requestSequence}';
    final record = await _durableKernel.submit(
      id: requestId,
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
