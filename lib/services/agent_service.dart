import 'dart:async';
import 'package:flutter/foundation.dart';
import '../agent/architecture/agent_kernel.dart' as execution;
import '../agent/architecture/agent_timeline_event.dart';
import '../agent/architecture/agent_event_bus.dart';
import '../domain/kernel/agent_kernel.dart' as durable;
import '../domain/kernel/agent_kernel_store.dart';
import '../domain/kernel/agent_observability.dart';
import '../domain/kernel/subagent_recovery_coordinator.dart';
import 'model_service.dart';
import 'stats_service.dart';
import 'analytics_service.dart';
import 'performance_service.dart';
import 'agent_background_execution_service.dart';
import '../domain/output/output_engine.dart';
import '../domain/mcp/mcp_client.dart';

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
        _store = AgentKernelStore.shared,
        _initializeExecutionRuntime = true {
    _models.bindKernelStore(_store);
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
        '$output\n\nتم حفظ النتائج المتاحة، لكن لم يكتمل التحقق من جميع المخرجات. ${collection.summary}',
      );
    }
    return output;
  }

  static bool _isInterruptedOutput(String output) =>
      output.startsWith('تم إيقاف التخطيط') ||
      output.startsWith('تم إيقاف المهمة') ||
      output.startsWith('تم إيقاف تنفيذ الوكيل') ||
      output.startsWith('تم إيقاف الوكيل بعد اكتمال الأداة') ||
      output.startsWith('تم إيقاف استدعاء الأداة المحدد') ||
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
        final eventType = event['type']?.toString() ?? '';
        if ((event['task_id']?.toString() ?? '').isNotEmpty &&
            eventType.startsWith('subagent_')) {
          await _store.recordSubagentEvent(event);
          if (event['is_async'] == true &&
              const {'subagent_completed', 'subagent_failed', 'subagent_interrupted', 'subagent_cancelled'}
                  .contains(eventType)) {
            try {
              await _refreshDetachedOutputs(event['request_id']?.toString() ?? '');
            } catch (_) {
              // A secondary artifact refresh must not block lifecycle journaling.
            }
          }
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

  /// Refreshes parent artifacts after a detached child reaches a terminal state.
  /// The parent request may still be finalizing when the child event arrives.
  Future<void> _refreshDetachedOutputs(String requestId) async {
    if (requestId.trim().isEmpty) return;
    KernelRequestRecord? request;
    for (var attempt = 0; attempt < 100; attempt++) {
      request = await _store.getRequest(requestId);
      if (request != null &&
          {'completed', 'interrupted', 'failed'}.contains(request.status)) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (request == null ||
        !{'completed', 'interrupted', 'failed'}.contains(request.status)) {
      return;
    }
    await _outputEngine.finalize(
      requestId: request.id,
      conversationId: request.conversationId,
      finalText: request.result ?? '',
      requestStatus: request.status,
      failure: request.error,
    );
  }

  Future<void> _initialize() async {
    // Bind analytics to the exact same store instance as request execution.
    await AnalyticsService().init(store: _store);
    // The execution runtime must be ready before queued durable work is drained.
    if (_initializeExecutionRuntime) await _executionKernel.initialize();
    _attachExecutionJournal();
    // Running requests are reconciled as interrupted; only never-started queued
    // requests may continue automatically, under a foreground service.
    await _store.reconcileAfterProcessRestart();
    // Reconcile child snapshots before the durable kernel starts draining the
    // queue, so newly launched children cannot be mistaken for old work.
    await _store.reconcileInterruptedSubagents();
    final interruptedAsyncParents = (await _store.getTasks())
        .where((task) => task['kind'] == 'subagent' &&
            task['is_async'] == true && task['status'] == 'interrupted')
        .map((task) => task['parent_request_id']?.toString() ?? '')
        .where((requestId) => requestId.isNotEmpty)
        .toSet();
    for (final requestId in interruptedAsyncParents) {
      try {
        await _refreshDetachedOutputs(requestId);
      } catch (_) {
        // Recovery metadata remains durable even if artifact refresh is unavailable.
      }
    }
    if (await _store.hasActiveRequests()) {
      await AgentBackgroundExecutionService.instance.beginTask(
        'متابعة قائمة المهام المحفوظة بعد إعادة تشغيل التطبيق',
      );
      unawaited(_releaseRecoveredQueueForegroundWhenIdle());
    }
    await _durableKernel.initialize();
    final pendingChildren = await _store.pendingAsyncSubagents();
    if (pendingChildren.isNotEmpty) {
      await AgentBackgroundExecutionService.instance.beginTask(
        'استعادة الوكلاء الفرعيين المؤجلين من الطابور الدائم',
      );
      for (final child in pendingChildren) {
        final requestId = child['parent_request_id']?.toString() ?? '';
        final conversationId = child['conversation_id']?.toString() ?? 'global';
        final agentId = child['subagent_id']?.toString() ?? '';
        if (requestId.isEmpty || agentId.isEmpty) continue;
        unawaited(_executionKernel.scheduleDynamicSubagent(
          requestId: requestId,
          conversationId: conversationId,
          agentId: agentId,
        ).catchError((Object _) {}));
      }
      unawaited(_releaseAsyncChildrenForegroundWhenIdle());
    }
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

  Future<void> _releaseAsyncChildrenForegroundWhenIdle() async {
    try {
      while (_executionKernel.isExecuting) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    } finally {
      await AgentBackgroundExecutionService.instance.endTask();
    }
  }

  Future<String> runTask(
    String prompt, {
    String conversationId = 'global',
    String? requestId,
  }) async {
    final stopwatch = Stopwatch()..start();
    await initialize();
    await AgentBackgroundExecutionService.instance.beginTask(prompt);
    var outcome = 'failed';
    try {
      unawaited(AnalyticsService().trackEvent('request_started').catchError((Object _) {}));

      final suppliedRequestId = requestId?.trim();
      final resolvedRequestId =
          suppliedRequestId == null || suppliedRequestId.isEmpty
              ? '${DateTime.now().microsecondsSinceEpoch}_${++_requestSequence}'
              : suppliedRequestId;
      // These are projections of the canonical durable request path: they do
      // not enqueue work, persist prompts, or create a second execution journal.
      final record = await _durableKernel.submit(
        id: resolvedRequestId,
        prompt: prompt,
        conversationId: conversationId,
      );
      await StatsService().incrementMessageCount();
      if (record.status == 'failed') {
        throw StateError(record.error ?? 'Agent request failed.');
      }
      if (record.status != 'completed' && record.status != 'interrupted') {
        throw StateError('Unexpected durable request state: ${record.status}');
      }
      outcome = record.status;
      return record.result ?? '';
    } finally {
      stopwatch.stop();
      PerformanceService().recordResponseTime(stopwatch.elapsedMilliseconds);
      unawaited(AnalyticsService().trackEvent('request_finished', data: <String, dynamic>{
        'status': outcome,
        'duration_ms': stopwatch.elapsedMilliseconds,
      }).catchError((Object _) {}));
      await _backgroundProgressTail;
      if (_executionKernel.isExecuting) {
        unawaited(_releaseAsyncChildrenForegroundWhenIdle());
      } else {
        await AgentBackgroundExecutionService.instance.endTask();
      }
    }
  }

  Future<KernelRequestRecord?> request(String requestId) =>
      _durableKernel.request(requestId);

  Future<List<KernelEventRecord>> eventsFor(String requestId) =>
      _durableKernel.eventsFor(requestId);

  /// Gain Agents diagnostics are queried through the same application service
  /// and durable store used by request execution. Screens must not open a
  /// parallel kernel database connection.
  Future<AgentObservabilitySummary> observabilitySummaryForConversation(
    String conversationId,
  ) async {
    await initialize();
    return _store.observabilitySummaryForConversation(conversationId);
  }

  Future<AgentObservabilityPage> observabilityEventsForConversation(
    String conversationId, {
    int? beforeRowId,
    int limit = 50,
    String? type,
    String? status,
    String? search,
  }) async {
    await initialize();
    return _store.observabilityEventsForConversation(
      conversationId,
      beforeRowId: beforeRowId,
      limit: limit,
      type: type,
      status: status,
      search: search,
    );
  }

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

  /// Returns all durable child snapshots owned by one chat/conversation.
  Future<List<Map<String, dynamic>>> subagentsForConversation(String conversationId) async {
    await initialize();
    return _store.subagentsForConversation(conversationId);
  }

  /// Returns the latest durable lifecycle snapshot for one child.
  Future<Map<String, dynamic>?> subagentStatus(String taskId) async {
    await initialize();
    return _store.getSubagent(taskId);
  }

  /// Dismisses a terminal child from active management without deleting its
  /// append-only audit history. Pending/running children cannot be dismissed.
  Future<bool> dismissSubagent(String taskId) async {
    await initialize();
    final child = await _store.getSubagent(taskId);
    if (child == null) return false;
    if (child['is_dismissed'] == true) return true;
    final status = child['status']?.toString() ?? 'unknown';
    if (status == 'pending' || status == 'running') return false;
    final requestId = child['parent_request_id']?.toString() ?? '';
    if (requestId.isEmpty) return false;
    AgentEventBus.instance.publish(<String, dynamic>{
      'id': 'subagent_dismissed_${taskId}_${DateTime.now().microsecondsSinceEpoch}',
      'request_id': requestId,
      'session_id': child['conversation_id']?.toString() ?? 'global',
      'task_id': taskId,
      'agent_type': child['agent_type']?.toString() ?? 'unknown',
      'title': child['title']?.toString() ?? taskId,
      'task_prompt': child['prompt']?.toString() ?? '',
      'depends_on': child['depends_on'] ?? const <String>[],
      'type': 'subagent_dismissed',
      'status': status,
      'details': 'Dismissed from active management; audit history retained.',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });
    await _flushExecutionJournal();
    return (await _store.getSubagent(taskId))?['is_dismissed'] == true;
  }

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
        final children = await _store.subagentsForRequest(parent.id);
        final allChildrenCompleted = children.isNotEmpty && children.every(
          (item) => item['status'] == 'completed' &&
              (item['last_result']?.toString() ?? '').trim().isNotEmpty,
        );
        if (allChildrenCompleted) {
          final finalText = await _executionKernel.synthesizeRecoveredRequest(
            requestId: parent.id,
            prompt: parent.prompt,
            conversationId: parent.conversationId,
            completedChildren: children,
          );
          await _flushExecutionJournal();
          final collection = await _outputEngine.finalize(
            requestId: parent.id,
            conversationId: parent.conversationId,
            finalText: finalText,
            requestStatus: 'completed',
          );
          await _flushExecutionJournal();
          if (collection.verified) {
            await _store.completeInterruptedRequest(parent.id, finalText);
            return finalText;
          }
          return '$finalText\n\nلم تُغلق المهمة بعد: ${collection.summary}';
        }
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

  /// MCP server configuration is persisted in secure storage; credentials are
  /// never copied into timeline events or model-visible server metadata.
  Future<List<McpServerConfig>> mcpServers() => McpClient.instance.servers();

  Future<void> addMcpServer({
    required String id,
    required String name,
    required String endpoint,
    String? bearerToken,
  }) => McpClient.instance.addServer(
        id: id,
        name: name,
        endpoint: endpoint,
        bearerToken: bearerToken,
      );

  Future<bool> removeMcpServer(String id) => McpClient.instance.removeServer(id);

  Future<List<McpRemoteTool>> refreshMcpTools(String serverId) =>
      McpClient.instance.listTools(serverId);

  /// Cancels one active tool invocation by its independent tool_call_id.
  bool cancelToolCall(String toolCallId) => _models.cancelToolCall(toolCallId);

  Future<bool> cancel() => _executionKernel.cancel();

  Future<bool> cancelSubagent(String taskId) =>
      _executionKernel.cancelSubagent(taskId);

  Future<Map<String, dynamic>> exportWorkspace() =>
      _executionKernel.exportWorkspace();

  Future<bool> shareWorkspace(List<String> paths) => _models.shareWorkspace(paths: paths);

  Future<bool> openWorkspaceFile(String path) =>
      _models.openWorkspaceFile(path: path);

  Future<Map<String, dynamic>> readImagePreview(String path) =>
      _models.readImagePreview(path: path);

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
