import 'dart:async';
import '../agent/architecture/agent_kernel.dart' as execution;
import '../agent/architecture/agent_timeline_event.dart';
import '../agent/architecture/agent_event_bus.dart';
import '../domain/kernel/agent_kernel.dart' as durable;
import '../domain/kernel/agent_kernel_store.dart';
import '../domain/kernel/subagent_recovery_coordinator.dart';
import 'model_service.dart';
import 'agent_background_execution_service.dart';
import '../domain/output/output_engine.dart';

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
  late final OutputEngine _outputEngine = OutputEngine(store: _store, models: _models);
  final bool _initializeExecutionRuntime;
  StreamSubscription<Map<String, dynamic>>? _eventSubscription;
  Future<void> _journalTail = Future<void>.value();
  Future<void> _backgroundProgressTail = Future<void>.value();
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
    } catch (error) {
      await instance._flushExecutionJournal();
      await instance._outputEngine.finalize(
        requestId: request.id,
        conversationId: request.conversationId,
        finalText: '',
        requestStatus: 'failed',
        failure: error.toString(),
      );
      await instance._flushExecutionJournal();
      rethrow;
    }
    await instance._flushExecutionJournal();
    final output = response.output;
    final interrupted = _isInterruptedOutput(output);
    final collection = await instance._outputEngine.finalize(
      requestId: request.id,
      conversationId: request.conversationId,
      finalText: output,
      requestStatus: interrupted ? 'interrupted' : 'completed',
    );
    await instance._flushExecutionJournal();
    if (interrupted) throw durable.KernelRequestInterrupted(output);
    if (!collection.verified) {
      throw durable.KernelRequestInterrupted(
        '$output\\n\\nتم حفظ النتائج المتاحة، لكن لم يكتمل التحقق من جميع المخرجات. ${collection.summary}',
      );
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
      // Token deltas are streamed to the chat renderer and are intentionally
      // excluded from the durable lifecycle journal to avoid unbounded growth.
      if (event['type'] == 'stream_token') return;
      _backgroundProgressTail = _backgroundProgressTail
          .then((_) => AgentBackgroundExecutionService.instance.updateTask(
                title: event['title']?.toString() ?? 'Giant Agent',
                body: event['details']?.toString() ??
                    '${event['status']?.toString() ?? 'قيد التنفيذ'} — ${event['type']?.toString() ?? 'تحديث'}',
              ))
          .catchError((Object _) {});
      _journalTail = _journalTail
          .then((_) async {
        if ((event['task_id']?.toString() ?? '').isNotEmpty) {
          await _store.recordSubagentEvent(event);
        }
        await _store.appendRequestEvent(event);
      }).catchError((Object _) {
        // Request completion remains owned by the durable kernel. A failed
        // supplemental timeline write must not corrupt the shared runtime.
      });
    });
  }

  Future<void> _flushExecutionJournal() async {
    // AgentEventBus uses an asynchronous broadcast stream. Let queued delivery
    // callbacks append their rows before waiting for the serialized write tail.
    await Future<void>.delayed(Duration.zero);
    await _journalTail;
  }

  Future<void> _initialize() async {
    // The execution runtime must be ready before queued durable work is drained.
    if (_initializeExecutionRuntime) await _executionKernel.initialize();
    _attachExecutionJournal();
    // Running requests are reconciled as interrupted; only never-started queued
    // requests may continue automatically, under a foreground service.
    await _store.reconcileAfterProcessRestart();
    // Reconcile child snapshots before the durable kernel starts draining the
    // queue, so newly launched children cannot be mistaken for old work.
    await _store.reconcileInterruptedSubagents();
    if (await _store.hasActiveRequests()) {
      await AgentBackgroundExecutionService.instance.beginTask(
        'متابعة قائمة المهام المحفوظة بعد إعادة تشغيل التطبيق',
      );
      unawaited(_releaseRecoveredQueueForegroundWhenIdle());
    }
    await _durableKernel.initialize();
    _initialized = true;
  }

  Future<void> _releaseRecoveredQueueForegroundWhenIdle() async {
    try {
      while (await _store.hasActiveRequests()) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    } catch (_) {
      // Stop monitoring if durable queue state can no longer be read.
    } finally {
      await AgentBackgroundExecutionService.instance.endTask();
    }
  }

  Future<String> runTask(
    String prompt, {
    String conversationId = 'global',
    String? requestId,
  }) async {
    await initialize();
    await AgentBackgroundExecutionService.instance.beginTask(prompt);
    try {
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
    } finally {
      await _backgroundProgressTail;
      await AgentBackgroundExecutionService.instance.endTask();
    }
  }

  Future<KernelRequestRecord?> request(String requestId) =>
      _durableKernel.request(requestId);

  Future<List<KernelEventRecord>> eventsFor(String requestId) =>
      _durableKernel.eventsFor(requestId);

  /// Returns saved artifacts (text, code, documents and media) for one request.
  Future<List<Map<String, dynamic>>> outputsForRequest(String requestId) =>
      _store.outputsForRequest(requestId);

  Future<List<Map<String, dynamic>>> outputsForConversation(String conversationId) =>
      _store.outputsForConversation(conversationId);

  /// Replays the immutable lifecycle journal for one child agent.
  Future<List<KernelEventRecord>> eventsForSubagent(String taskId) =>
      _store.taskEvents(taskId);

  /// Returns durable child snapshots for a request, including safely interrupted work.
  Future<List<Map<String, dynamic>>> subagentsForRequest(String requestId) =>
      _store.subagentsForRequest(requestId);

  /// Resumes one interrupted child only after an explicit user decision about
  /// possible side effects. The child reuses the process-wide execution kernel.
  Future<String> resumeSubagent(
    String taskId, {
    required String sideEffectDisposition,
  }) async {
    await initialize();
    await AgentBackgroundExecutionService.instance.beginTask('استئناف الوكيل الفرعي $taskId');
    try {
      final recovery = SubagentRecoveryCoordinator(_store);
      final resumedOutput = await recovery.resume(
        taskId: taskId,
        sideEffectDisposition: sideEffectDisposition,
        execute: ({required parent, required task, required dependencyResults}) async {
          try {
            return await _executionKernel.executeRecoveredSubagent(
              parentRequestId: parent.id,
              parentPrompt: parent.prompt,
              conversationId: parent.conversationId,
              taskId: taskId,
              title: task['title']?.toString() ?? taskId,
              taskPrompt: task['prompt']?.toString() ?? '',
              agentType: task['agent_type']?.toString() ?? 'explore',
              dependencyResults: dependencyResults,
            );
          } finally {
            await _flushExecutionJournal();
          }
        },
      );
      await _flushExecutionJournal();
      final child = await _store.getSubagent(taskId);
      final parentId = child?['parent_request_id']?.toString() ?? '';
      final parent = parentId.isEmpty ? null : await _store.getRequest(parentId);
      if (parent != null) {
        await _outputEngine.finalize(
          requestId: parent.id,
          conversationId: parent.conversationId,
          finalText: parent.result ?? '',
          requestStatus: 'interrupted',
        );
        await _flushExecutionJournal();
      }
      return resumedOutput;
    } finally {
      await _backgroundProgressTail;
      await AgentBackgroundExecutionService.instance.endTask();
    }
  }

  Future<bool> cancel() => _executionKernel.cancel();

  Future<bool> cancelSubagent(String taskId) =>
      _executionKernel.cancelSubagent(taskId);

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
  Future<void> disposeForTesting() async {
    await _flushExecutionJournal();
    await _eventSubscription?.cancel();
    await _durableKernel.dispose();
  }
}
