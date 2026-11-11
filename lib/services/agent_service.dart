import 'dart:async';
import '../agent/architecture/agent_kernel.dart' as execution;
import '../agent/architecture/agent_timeline_event.dart';
import '../agent/architecture/agent_event_bus.dart';
import '../agent/architecture/subagent_tool_bridge.dart';
import '../domain/kernel/agent_kernel.dart' as durable;
import '../domain/kernel/agent_kernel_store.dart';
import '../domain/kernel/subagent_recovery_coordinator.dart';
import 'model_service.dart';
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

  void _configureSubagentToolBridge() {
    SubagentToolBridge.instance.configure(
      create: (parentRequestId, arguments, toolCallId) async {
        final rawDependencies = arguments['depends_on'];
        if (rawDependencies != null && rawDependencies is! List) {
          throw const FormatException('depends_on must be an array of child task ids.');
        }
        final child = await createSubagent(
          parentRequestId: parentRequestId,
          taskId: arguments['id']?.toString() ?? '',
          title: arguments['title']?.toString() ?? '',
          prompt: arguments['prompt']?.toString() ?? '',
          agentType: arguments['agent_type']?.toString() ?? 'explore',
          dependsOn: (rawDependencies as List? ?? const [])
              .map((value) => value.toString()).toList(growable: false),
          toolCallId: toolCallId,
        );
        return <String, dynamic>{'ok': true, 'subagent': child};
      },
      spawn: (parentRequestId, arguments, toolCallId) async {
        final taskId = arguments['task_id']?.toString() ?? '';
        try {
          final child = await spawnSubagent(
            taskId,
            expectedParentRequestId: parentRequestId,
            toolCallId: toolCallId,
          );
          final completed = child['status'] == 'completed' &&
              (child['last_result']?.toString() ?? '').trim().isNotEmpty;
          return <String, dynamic>{
            'ok': completed,
            'subagent': child,
            if (!completed)
              'error': 'Subagent ended in state ${child['status']}; no verified completed result is available.',
          };
        } catch (error) {
          return <String, dynamic>{'ok': false, 'error': error.toString()};
        }
      },
      check: (parentRequestId, arguments, _) async {
        final taskId = arguments['task_id']?.toString() ?? '';
        final child = await checkSubagentStatus(
          taskId,
          expectedParentRequestId: parentRequestId,
        );
        if (child == null) {
          return <String, dynamic>{'ok': false, 'error': 'Subagent not found for the active parent request.'};
        }
        return <String, dynamic>{'ok': true, 'subagent': child};
      },
      delete: (parentRequestId, arguments, _) async {
        final taskId = arguments['task_id']?.toString() ?? '';
        final deleted = await deleteSubagent(
          taskId,
          expectedParentRequestId: parentRequestId,
        );
        return <String, dynamic>{
          'ok': deleted,
          'deleted': deleted,
          if (!deleted) 'error': 'The child was not found, belongs to another parent, or is still active.',
        };
      },
      list: (parentRequestId, _, __) async => <String, dynamic>{
        'ok': true,
        'subagents': await listSubagents(parentRequestId),
      },
    );
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
    _configureSubagentToolBridge();
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

  /// Returns the latest durable lifecycle snapshot for one child.
  Future<Map<String, dynamic>?> subagentStatus(String taskId) async {
    await initialize();
    return _store.getSubagent(taskId);
  }

  final Set<String> _spawningSubagents = <String>{};

  /// Creates a durable child-agent definition without starting execution.
  /// The append-only event journal remains the source of lifecycle history.
  Future<Map<String, dynamic>> createSubagent({
    required String parentRequestId,
    required String taskId,
    required String title,
    required String prompt,
    String agentType = 'explore',
    List<String> dependsOn = const <String>[],
    String toolCallId = '',
  }) async {
    await initialize();
    final id = taskId.trim();
    final cleanTitle = title.trim();
    final cleanPrompt = prompt.trim();
    if (id.isEmpty || cleanTitle.isEmpty || cleanPrompt.isEmpty) {
      throw ArgumentError('Subagent id, title and prompt are required.');
    }
    if (cleanPrompt.length > 12000 || cleanTitle.length > 160) {
      throw ArgumentError('Subagent title or prompt exceeds the supported limit.');
    }
    if (!const {'explore', 'plan', 'coder', 'reviewer'}.contains(agentType)) {
      throw ArgumentError('Unknown subagent type: $agentType');
    }
    if (dependsOn.length > 8 || dependsOn.toSet().length != dependsOn.length ||
        dependsOn.contains(id)) {
      throw ArgumentError('Subagent dependencies must be unique and cannot include itself.');
    }
    final parent = await _store.getRequest(parentRequestId);
    if (parent == null) {
      throw StateError('Parent request $parentRequestId does not exist.');
    }
    final children = await _store.subagentsForRequest(parentRequestId);
    if (children.length >= 8) {
      throw StateError('A request may own at most eight subagents.');
    }
    if (await _store.getSubagent(id) != null) {
      throw StateError('Subagent id already exists: $id');
    }
    for (final dependencyId in dependsOn) {
      final dependency = await _store.getSubagent(dependencyId);
      if (dependency == null ||
          dependency['parent_request_id'] != parentRequestId) {
        throw StateError('Dependency $dependencyId is not a child of this request.');
      }
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await _store.recordSubagentEvent(<String, dynamic>{
      'id': 'subagent_created_${id}_${DateTime.now().microsecondsSinceEpoch}',
      'request_id': parentRequestId,
      'session_id': parent.conversationId,
      'task_id': id,
      'agent_type': agentType,
      'title': cleanTitle,
      'task_prompt': cleanPrompt,
      'depends_on': dependsOn,
      'type': 'subagent_created',
      'status': 'pending',
      if (toolCallId.isNotEmpty) 'tool_call_id': toolCallId,
      'details': 'Created and durably registered; execution has not started.',
      'timestamp': now,
    });
    final created = await _store.getSubagent(id);
    if (created == null || created['status'] != 'pending') {
      throw StateError('Subagent creation was not durably confirmed.');
    }
    return created;
  }

  /// Starts one pending child through the existing shared AgentKernel runtime.
  /// A second local model/JNI runtime is never created.
  Future<Map<String, dynamic>> spawnSubagent(
    String taskId, {
    String? expectedParentRequestId,
    String toolCallId = '',
  }) async {
    await initialize();
    final id = taskId.trim();
    if (id.isEmpty) throw ArgumentError('Subagent id is required.');
    if (!_spawningSubagents.add(id)) {
      throw StateError('Subagent $id is already being spawned.');
    }
    try {
      final child = await _store.getSubagent(id);
      if (child == null) throw StateError('Subagent $id was not found.');
      if (expectedParentRequestId != null &&
          child['parent_request_id'] != expectedParentRequestId) {
        throw StateError('Subagent $id does not belong to the active parent request.');
      }
      if (child['is_dismissed'] == true) {
        throw StateError('Dismissed subagents cannot be spawned.');
      }
      if (child['status'] != 'pending') {
        throw StateError('Only pending subagents can be spawned; current state: ${child['status']}.');
      }
      final parentId = child['parent_request_id']?.toString() ?? '';
      final parent = await _store.getRequest(parentId);
      if (parent == null) throw StateError('Parent request $parentId was not found.');
      final dependencyResults = <String, String>{};
      final dependencies = child['depends_on'];
      if (dependencies is List) {
        for (final rawId in dependencies) {
          final dependencyId = rawId.toString();
          final dependency = await _store.getSubagent(dependencyId);
          if (dependency == null || dependency['parent_request_id'] != parentId ||
              dependency['status'] != 'completed') {
            throw StateError('Dependency $dependencyId must complete before this subagent can start.');
          }
          final result = dependency['last_result']?.toString() ?? '';
          if (result.trim().isEmpty) {
            throw StateError('Dependency $dependencyId has no completed result.');
          }
          dependencyResults[dependencyId] = result;
        }
      }
      await AgentBackgroundExecutionService.instance.beginTask(
        'تشغيل الوكيل الفرعي: ${child['title'] ?? id}',
      );
      try {
        await _executionKernel.executeDynamicSubagent(
          parentRequestId: parent.id,
          conversationId: parent.conversationId,
          taskId: id,
          title: child['title']?.toString() ?? id,
          taskPrompt: child['prompt']?.toString() ?? '',
          agentType: child['agent_type']?.toString() ?? 'explore',
          dependencyResults: dependencyResults,
          toolCallId: toolCallId,
        );
      } finally {
        await _flushExecutionJournal();
        await AgentBackgroundExecutionService.instance.endTask();
      }
      final completed = await _store.getSubagent(id);
      if (completed == null) throw StateError('Subagent state disappeared after execution.');
      return completed;
    } finally {
      _spawningSubagents.remove(id);
    }
  }

  /// Kimi-compatible delete is a soft delete: terminal state and audit events
  /// remain durable; active or pending workers cannot be removed.
  Future<bool> deleteSubagent(
    String taskId, {
    String? expectedParentRequestId,
  }) async {
    await initialize();
    if (_spawningSubagents.contains(taskId)) return false;
    if (expectedParentRequestId != null) {
      final child = await _store.getSubagent(taskId);
      if (child == null || child['parent_request_id'] != expectedParentRequestId) {
        return false;
      }
    }
    final deleted = await _store.dismissSubagent(taskId);
    await _flushExecutionJournal();
    return deleted;
  }

  /// Explicit status contract used by orchestration and recovery callers.
  Future<Map<String, dynamic>?> checkSubagentStatus(
    String taskId, {
    String? expectedParentRequestId,
  }) async {
    final child = await subagentStatus(taskId);
    if (child == null ||
        (expectedParentRequestId != null &&
            child['parent_request_id'] != expectedParentRequestId)) {
      return null;
    }
    return child;
  }

  /// Lists all durable children for one parent in creation order.
  Future<List<Map<String, dynamic>>> listSubagents(String parentRequestId) async {
    await initialize();
    return _store.subagentsForRequest(parentRequestId);
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
