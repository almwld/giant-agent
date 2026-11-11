import 'dart:async';
import 'dart:convert';

import '../../services/agent_memory_service.dart';
import '../../services/model_service.dart';
import '../../services/openai_compatible_provider.dart';
import '../../services/model_provider_settings.dart';
import '../../services/planner_service.dart';
import 'agent_timeline_event.dart';
import 'agent_event_bus.dart';
import 'fifo_task_queue.dart';
import 'subagent_orchestrator.dart';

/// Lifecycle states exposed by the agent orchestration layer.
enum AgentKernelState {
  idle,
  initializing,
  executing,
  cancelling,
  failed,
}

/// Immutable request passed through the orchestration boundary.
class AgentRequest {
  const AgentRequest({
    required this.id,
    required this.prompt,
    this.conversationId = 'global',
  });

  final String id;
  final String prompt;
  final String conversationId;
}

/// Result envelope keeps the runtime output separate from execution metadata.
class AgentResponse {
  const AgentResponse({
    required this.requestId,
    required this.output,
    required this.completedAt,
  });

  final String requestId;
  final String output;
  final DateTime completedAt;
}

/// Central orchestration boundary for the local-first agent.
///
/// The kernel owns request admission, runtime readiness, lifecycle events and
/// cancellation. ModelService remains responsible for local inference, memory
/// retrieval and bounded tool execution.
class AgentKernel {
  AgentKernel._();

  static final AgentKernel instance = AgentKernel._();

  final ModelService _models = ModelService();
  final PlannerService _planner = PlannerService();
  final StreamController<AgentTimelineEvent> _events =
      StreamController<AgentTimelineEvent>.broadcast();

  AgentKernelState _state = AgentKernelState.idle;
  String? _activeRequestId;
  Future<void>? _initialization;
  int _eventSequence = 0;
  bool _cancellationRequested = false;
  SubagentOrchestrator? _activeSubagentOrchestrator;
  final Set<String> _activeSubagentIds = <String>{};
  final Set<String> _cancelledSubagentIds = <String>{};
  String? _activeSubagentParentRequestId;
  final FifoTaskQueue _requestQueue = FifoTaskQueue();
  int get queuedRequestCount => _requestQueue.pendingCount;

  AgentKernelState get state => _state;
  String? get activeRequestId => _activeRequestId;
  Stream<AgentTimelineEvent> get events => _events.stream;

  bool get isExecuting =>
      _activeRequestId != null || _requestQueue.isRunning || _requestQueue.pendingCount > 0 ||
      _state == AgentKernelState.executing || _state == AgentKernelState.cancelling;

  void _emit({
    required String requestId,
    required String type,
    required String title,
    required String status,
    String? details,
    String? result,
    String? eventId,
    String? taskId,
    String? agentType,
    String? taskPrompt,
    List<String>? dependsOn,
  }) {
    final sequence = ++_eventSequence;
    final event = AgentTimelineEvent(
      // Every transition receives a new identity. eventId is retained only as
      // the logical step correlation key, never as a replaceable event ID.
      id: 'kernel_${requestId}_event_$sequence',
      requestId: requestId,
      attemptId: requestId,
      stepId: eventId ?? '${requestId}_$type',
      sequence: sequence,
      type: type,
      title: title,
      status: status,
      timestamp: DateTime.now(),
      details: details,
      result: result,
      taskId: taskId,
      agentType: agentType,
      taskPrompt: taskPrompt,
      dependsOn: dependsOn ?? const <String>[],
    );
    _events.add(event);
    AgentEventBus.instance.publish(event.toMap());
  }

  /// Concurrent callers share one initialization future instead of racing
  /// model discovery/loading against one another.
  Future<void> initialize() {
    final inFlight = _initialization;
    if (inFlight != null) return inFlight;

    late final Future<void> shared;
    shared = _initialize().whenComplete(() {
      if (identical(_initialization, shared)) _initialization = null;
    });
    _initialization = shared;
    return shared;
  }

  Future<void> _initialize() async {
    _state = AgentKernelState.initializing;
    _emit(
      requestId: 'runtime',
      eventId: 'kernel_runtime_initialization',
      type: 'runtime_initializing',
      title: 'تهيئة محرك الوكيل',
      status: 'running',
    );
    try {
      await _models.init();
      _state = AgentKernelState.idle;
      _emit(
        requestId: 'runtime',
        eventId: 'kernel_runtime_initialization',
        type: 'runtime_ready',
        title: 'محرك الوكيل جاهز',
        status: 'completed',
        details: 'اكتملت تهيئة مكتبة النماذج المحلية.',
      );
    } catch (error) {
      _state = AgentKernelState.failed;
      _emit(
        requestId: 'runtime',
        eventId: 'kernel_runtime_initialization',
        type: 'runtime_initialization_failed',
        title: 'تعذرت تهيئة محرك الوكيل',
        status: 'failed',
        details: error.toString(),
      );
      rethrow;
    } finally {
      if (_state == AgentKernelState.failed) _state = AgentKernelState.idle;
    }
  }

  /// FIFO admission: each caller receives the result of its own request.
  Future<AgentResponse> execute(AgentRequest request) {
    if (request.prompt.trim().isEmpty) {
      return Future<AgentResponse>.error(ArgumentError.value(
        request.prompt, 'prompt', 'Task must not be empty.',
      ));
    }
    AgentEventBus.instance.bindRequest(request.id, request.conversationId);
    final hadActiveRequest = _activeRequestId != null || _requestQueue.isRunning;
    _emit(
      requestId: request.id,
      type: 'request_queued',
      title: hadActiveRequest ? 'الطلب في قائمة الانتظار' : 'تمت إضافة الطلب إلى قائمة التنفيذ',
      status: 'pending',
      details: 'موضع الطلب: ${_requestQueue.pendingCount + 1}.',
    );
    return _requestQueue.enqueue(() => _executeAdmitted(request));
  }

  Future<AgentResponse> _executeAdmitted(AgentRequest request) async {
    final prompt = request.prompt.trim();
    if (prompt.isEmpty) {
      throw ArgumentError.value(
        request.prompt,
        'prompt',
        'Task must not be empty.',
      );
    }
    _activeRequestId = request.id;
    _cancellationRequested = false;
    _models.beginAgentRequest(request.id);

    try {
      // Start the protected section immediately after reserving the slot so
      // every subsequent operation is covered by the release in finally.
      _emit(
        requestId: request.id,
        type: 'request_received',
        title: 'تم استلام الطلب',
        // Receipt is not execution; only a real completed operation is green.
        status: 'pending',
      );
      final selectedMode = await ModelProviderSettings.instance.getMode();
      final openRouterEnabled = selectedMode == ModelProviderMode.openRouter &&
          await OpenAICompatibleProvider.instance.isEnabled();
      if (!openRouterEnabled) {
        if (!_models.hasActiveModel()) {
          throw StateError(
            'Load a local GGUF model or configure an external API provider before starting an agent task.',
          );
        }

        final nativeModelLoaded = await _models.isModelLoaded();
        if (!nativeModelLoaded) {
          throw StateError(
            'The selected GGUF model is not loaded in the native runtime.',
          );
        }
      }

      _emit(
        requestId: request.id,
        type: 'model_ready',
        title: openRouterEnabled
            ? 'تم التحقق من اتصال المزوّد الخارجي'
            : 'تم التحقق من جاهزية النموذج المحلي',
        status: 'completed',
        details: openRouterEnabled
            ? 'سيستخدم الوكيل النموذج الخارجي المحدد.'
            : 'سيستخدم الوكيل نموذج GGUF المحلي.',
      );

      _state = AgentKernelState.executing;
      _emit(
        requestId: request.id,
        eventId: 'kernel_${request.id}_execution',
        type: 'execution_started',
        title: 'بدأ تنفيذ الطلب',
        status: 'running',
      );

      final output = await _executePlannedRequest(
        prompt,
        requestId: request.id,
        conversationId: request.conversationId,
      );
      final normalizedOutput = output.trim();
      // The coordinator flag is authoritative even if a provider finishes
      // its in-flight request before it can observe the cancellation signal.
      final wasCancelled =
          _cancellationRequested || _isCancelledOutput(normalizedOutput);
      final executionWasBounded = _isIncompleteOutput(normalizedOutput);

      if (wasCancelled || executionWasBounded) {
        _state = AgentKernelState.idle;
        _emit(
          requestId: request.id,
          eventId: 'kernel_${request.id}_execution',
          type: wasCancelled ? 'execution_interrupted' : 'execution_incomplete',
          title: wasCancelled
              ? 'توقف التنفيذ بطلب المستخدم'
              : 'توقف التنفيذ قبل اكتمال المهمة',
          status: 'interrupted',
          details: wasCancelled
              ? 'أعاد المحرك المحلي حالة الإيقاف؛ لم يُعلن اكتمال المهمة.'
              : 'وصل التنفيذ إلى حد الأمان أو اكتشف تكرارًا دون تقدم.',
        );
        return AgentResponse(
          requestId: request.id,
          output: output,
          completedAt: DateTime.now(),
        );
      }
      if (_isFailureOutput(normalizedOutput)) {
        throw StateError(
          normalizedOutput.isEmpty
              ? 'The agent runtime returned an empty response.'
              : normalizedOutput,
        );
      }

      _state = AgentKernelState.idle;
      _emit(
        requestId: request.id,
        eventId: 'kernel_${request.id}_execution',
        type: 'response_generated',
        title: 'اكتمل توليد الإجابة',
        status: 'completed',
        details: 'اكتمل التوليد المحلي؛ وتُعرض نتائج الأدوات الفعلية كأحداث مستقلة.',
      );
      return AgentResponse(
        requestId: request.id,
        output: output,
        completedAt: DateTime.now(),
      );
    } catch (error) {
      _state = AgentKernelState.failed;
      _emit(
        requestId: request.id,
        eventId: 'kernel_${request.id}_execution',
        type: 'execution_failed',
        title: 'تعذر إكمال الطلب',
        status: 'failed',
        details: error.toString(),
      );
      rethrow;
    } finally {
      _models.endAgentRequest(request.id);
      AgentEventBus.instance.unbindRequest(request.id);
      _activeRequestId = null;
      _cancellationRequested = false;
      if (_state == AgentKernelState.failed ||
          _state == AgentKernelState.executing ||
          _state == AgentKernelState.cancelling) {
        _state = AgentKernelState.idle;
      }
    }
  }


  /// Executes one explicitly recovered child through the existing shared ModelService.
  /// This never creates a second model/JNI runtime and refuses to overlap a parent request.
  Future<String> executeRecoveredSubagent({
    required String parentRequestId,
    required String parentPrompt,
    required String conversationId,
    required String taskId,
    required String title,
    required String taskPrompt,
    required String agentType,
    required Map<String, String> dependencyResults,
  }) => _requestQueue.enqueue(() => _executeRecoveredSubagentAdmitted(
    parentRequestId: parentRequestId,
    parentPrompt: parentPrompt,
    conversationId: conversationId,
    taskId: taskId,
    title: title,
    taskPrompt: taskPrompt,
    agentType: agentType,
    dependencyResults: dependencyResults,
  ));

  Future<String> _executeRecoveredSubagentAdmitted({
    required String parentRequestId,
    required String parentPrompt,
    required String conversationId,
    required String taskId,
    required String title,
    required String taskPrompt,
    required String agentType,
    required Map<String, String> dependencyResults,
  }) async {
    if (taskId.trim().isEmpty || taskPrompt.trim().isEmpty) {
      throw ArgumentError('Recovered child identity and prompt are required.');
    }
    final requestId = 'resume_${parentRequestId}_${taskId}_${DateTime.now().microsecondsSinceEpoch}';
    _activeRequestId = requestId;
    _activeSubagentIds.add(taskId);
    _activeSubagentParentRequestId = parentRequestId;
    _cancellationRequested = false;
    _models.beginAgentRequest(requestId);
    try {
      final selectedMode = await ModelProviderSettings.instance.getMode();
      final providerEnabled = selectedMode == ModelProviderMode.openRouter &&
          await OpenAICompatibleProvider.instance.isEnabled();
      if (!providerEnabled) {
        if (!_models.hasActiveModel() || !await _models.isModelLoaded()) {
          throw StateError('يجب تحميل النموذج المحلي قبل استئناف الوكيل الفرعي.');
        }
      }
      final dependencyContext = dependencyResults.entries.map((entry) =>
        'نتيجة المهمة السابقة ${entry.key}:\n${entry.value}'
      ).join('\n\n');
      final allowedTools = switch (agentType) {
        'explore' || 'plan' || 'reviewer' => const <String>{'read_file', 'list_files', 'web_search', 'mcp_call', 'mcp_read_resource'},
        'coder' => const <String>{'create_file', 'read_file', 'write_file', 'list_files', 'web_search', 'execute_python', 'gain_terminal', 'mcp_call', 'mcp_read_resource'},
        _ => throw ArgumentError('Unknown recovered agent type: $agentType'),
      };
      _emit(requestId: parentRequestId, taskId: taskId, agentType: agentType,
        taskPrompt: taskPrompt, type: 'subagent_resume_started',
        title: 'استئناف الوكيل الفرعي: $title', status: 'running');
      final prompt = '''أنت وكيل فرعي مستأنف من نوع $agentType.\nالمهمة الأصلية: $parentPrompt\nالمهمة المسندة: $taskPrompt\nنتائج التبعيات المكتملة:\n${dependencyContext.isEmpty ? 'لا توجد تبعيات.' : dependencyContext}\n\nقواعد الاستئناف:\n- افحص الحالة الحالية قبل أي تعديل؛ قد تكون بعض الآثار الجانبية نُفذت قبل الانقطاع.\n- لا تكرر عملية غير قابلة للعكس أو إرسالاً أو حذفاً أو دفعاً أو شراءً دون تحقق من حالتها وموافقة المستخدم عند الحاجة.\n- أكمل الجزء المتبقي فقط، ولا تفترض أن سياق النموذج السابق ما زال موجوداً.\n- استخدم الأدوات المسموح بها فقط، ولا تدّع نجاح عملية دون دليل.\n- أعد النتيجة والأدلة والملفات التي تغيرت وما بقي غير منجز.''';
      final output = (await _models.processInput(prompt,
        conversationId: '$conversationId::subagent::$taskId',
        persistTurn: false, allowedTools: allowedTools,
        shouldCancel: () => _cancellationRequested || _cancelledSubagentIds.contains(taskId),
        requestId: parentRequestId,
        taskId: taskId,
        agentType: agentType)).trim();
      if (_cancellationRequested || _isCancelledOutput(output) || _isIncompleteOutput(output)) {
        throw SubagentInterrupted(output.isEmpty ? 'تم إيقاف استئناف الوكيل الفرعي.' : output);
      }
      if (_isFailureOutput(output)) throw StateError(output);
      _emit(requestId: parentRequestId, taskId: taskId, agentType: agentType,
        taskPrompt: taskPrompt, type: 'subagent_resume_completed',
        title: 'اكتمل استئناف الوكيل الفرعي: $title', status: 'completed',
        details: output.length > 1200 ? '${output.substring(0, 1200)}…' : output,
        result: output);
      return output;
    } on SubagentInterrupted catch (error) {
      _emit(requestId: parentRequestId, taskId: taskId, agentType: agentType,
        taskPrompt: taskPrompt, type: 'subagent_resume_interrupted',
        title: 'توقف استئناف الوكيل الفرعي: $title', status: 'interrupted',
        details: error.toString());
      rethrow;
    } catch (error) {
      _emit(requestId: parentRequestId, taskId: taskId, agentType: agentType,
        taskPrompt: taskPrompt, type: 'subagent_resume_failed',
        title: 'تعذر استئناف الوكيل الفرعي: $title', status: 'failed',
        details: error.toString());
      rethrow;
    } finally {
      _models.endAgentRequest(requestId);
      _activeRequestId = null;
      _activeSubagentIds.remove(taskId);
      _cancelledSubagentIds.remove(taskId);
      if (_activeSubagentParentRequestId == parentRequestId) _activeSubagentParentRequestId = null;
      _cancellationRequested = false;
      if (_state != AgentKernelState.failed) _state = AgentKernelState.idle;
    }
  }

  bool _isCancelledOutput(String output) =>
      output.startsWith('تم إيقاف التخطيط') ||
      output.startsWith('تم إيقاف المهمة') ||
      output.startsWith('تم إيقاف تنفيذ الوكيل') ||
      output.startsWith('تم إيقاف الوكيل بعد اكتمال الأداة') ||
      output.startsWith('تم إيقاف استدعاء الأداة المحدد') ||
      output.startsWith('تم إيقاف التوليد') ||
      output.contains('[تم إيقاف التوليد]');

  bool _isIncompleteOutput(String output) =>
      output.startsWith('وصل الوكيل إلى الحد الآمن') ||
      output.startsWith('أوقف الوكيل تكرار استدعاء الأداة');

  bool _isFailureOutput(String output) =>
      output.isEmpty ||
      output.startsWith('ERROR:') ||
      output.startsWith('تعذر تشغيل النموذج المحلي:') ||
      output.startsWith('تعذر تحليل استدعاء الأداة أو تنفيذه:') ||
      output.startsWith('تعذر إكمال الطلب:') ||
      output.startsWith('⚠️ اختر نموذج') ||
      output.startsWith('⚠️ استورد نموذج');

  Future<String> _executePlannedRequest(
    String prompt, {
    required String requestId,
    required String conversationId,
  }) async {
    if (!_planner.requiresPlan(prompt)) {
      return _models.processInput(prompt, conversationId: conversationId,
        requestId: requestId, shouldCancel: () => _cancellationRequested);
    }

    final softwareScope = RegExp(
      r'(كود|تطبيق|موقع|برنامج|مستودع|نظام|قاعدة|واجهة|نواة|api|flutter|dart|javascript|software|code|app|website|project|repository|kernel|agent|workflow)',
    ).hasMatch(prompt.toLowerCase());
    final implementationIntent = RegExp(
      r'(برمج|أنشئ|انشئ|ابن|طور|نفذ|صمم|اكتب كود|أصلح|اصلح|عدّل|عدل|ادمج|حدّث|حدث|واصل|اكمل|أكمل|استكمل|implement|create|build|develop|refactor|debug|fix|write code|integrate|modify|complete|finish)',
    ).hasMatch(prompt.toLowerCase());
    final isSoftwareTask = softwareScope && implementationIntent;

    _emit(
      requestId: requestId,
      type: 'delegation_planning_started',
      title: 'يحلل الوكيل الرئيسي المهمة ويحدد الوكلاء المناسبين',
      status: 'running',
    );

    var planSource = 'model';
    var tasks = <SubagentTask>[];
    try {
      final modelPlan = await _models.generateStructuredOutput(
        prompt,
        conversationId: '$conversationId::planner::$requestId',
        shouldCancel: () => _cancellationRequested,
      );
      if (_cancellationRequested || modelPlan.startsWith('تم إيقاف التخطيط')) {
        return 'تم إيقاف التخطيط قبل تشغيل الوكلاء الفرعيين.';
      }
      tasks = _parseSubagentPlan(
        modelPlan,
        requestId: requestId,
        allowCoder: isSoftwareTask,
      );
    } catch (_) {
      // Small local models may not reliably emit JSON. Fall back to the
      // deterministic, validated plan rather than failing the user's task.
      planSource = 'deterministic_fallback';
    }

    if (tasks.isEmpty) {
      planSource = 'deterministic_fallback';
      tasks = _fallbackSubagentPlan(
        prompt,
        requestId: requestId,
        allowCoder: isSoftwareTask,
      );
    }

    _emit(
      requestId: requestId,
      type: 'plan_created',
      title: planSource == 'model'
          ? 'أنشأ الوكيل الرئيسي خطة تفويض منظمة'
          : 'استخدم الوكيل الرئيسي خطة احتياطية موثوقة',
      status: 'completed',
      details: jsonEncode(<String, Object?>{
        'source': planSource,
        'tasks': tasks.map((task) => <String, Object?>{
          'task_id': task.id,
          'agent_type': task.agentType,
          'title': task.title,
          'depends_on': task.dependsOn,
        }).toList(),
      }),
    );

    final selectedMode = await ModelProviderSettings.instance.getMode();
    final cloudParallelismEnabled = selectedMode == ModelProviderMode.openRouter &&
        await OpenAICompatibleProvider.instance.isEnabled();
    final workerConcurrency = cloudParallelismEnabled ? 3 : 1;
    final orchestrator = SubagentOrchestrator(
      parentRequestId: requestId,
      conversationId: conversationId,
      // The mutable llama.cpp JNI context remains strictly single-worker.
      // OpenRouter calls have request-scoped zones; workspace side effects are
      // separately serialized by ModelService's tool FIFO.
      maxConcurrency: workerConcurrency,
      onEvent: (event) {
        final taskId = event['task_id']?.toString() ?? '';
        _emit(
          requestId: requestId,
          eventId: taskId,
          taskId: taskId,
          agentType: event['agent_type']?.toString(),
          taskPrompt: event['task_prompt']?.toString(),
          dependsOn: (event['depends_on'] as List?)?.map((item) => item.toString()).toList(growable: false) ?? const <String>[],
          type: event['type']?.toString() ?? 'subagent_event',
          title: event['title']?.toString() ?? 'تحديث الوكيل الفرعي',
          status: event['status']?.toString() ?? 'pending',
          details: event['details']?.toString(),
          result: event['result']?.toString(),
        );
      },
      execute: (task, dependencyResults, isTaskCancelled) async {
        if (_cancellationRequested) {
          throw const SubagentInterrupted('أوقف المستخدم تنفيذ الوكلاء الفرعيين.');
        }

        final dependencyContext = dependencyResults.entries.map((entry) {
          final result = entry.value;
          return '''
نتيجة المهمة السابقة ${entry.key}:
الحالة: ${result.status}
${result.output ?? result.error ?? 'لا توجد نتيجة نصية.'}
''';
        }).join('\n');

        final allowedTools = switch (task.agentType) {
          'explore' || 'plan' || 'reviewer' =>
            const <String>{'read_file', 'list_files', 'web_search', 'mcp_call', 'mcp_read_resource'},
          'coder' => const <String>{
              'create_file',
              'read_file',
              'write_file',
              'list_files',
              'execute_python',
              'gain_terminal',
              'mcp_call',
              'mcp_read_resource',
            },
          _ => const <String>{'read_file', 'list_files'},
        };

        final isolatedConversationId =
            '$conversationId::subagent::${task.id}';
        final subagentPrompt = '''
أنت وكيل فرعي مستقل من نوع ${task.agentType}.
المهمة الأصلية للمستخدم:
$prompt

المهمة المسندة إليك:
${task.prompt}

نتائج الوكلاء السابقين:
${dependencyContext.isEmpty ? 'لا توجد تبعيات سابقة.' : dependencyContext}

قواعد التنفيذ:
- اعمل داخل نطاق المهمة المسندة فقط ولا تنشئ وكلاء فرعيين.
- هذا سياق معزول؛ لا تفترض أنك ترى سجل المحادثة الرئيسي.
- استخدم الأدوات المسموح بها فقط، ولا تدّع تنفيذ عملية دون نتيجة أداة مؤكدة.
- وكيل explore وplan وreviewer للقراءة والتحليل فقط؛ لا تعدّل الملفات.
- وكيل coder يمكنه تعديل مساحة العمل، وأوامر الطرفية تظل خاضعة لموافقة المستخدم.
- أعد نتيجة عملية موجزة، والأدلة، والملفات أو الأدوات التي استخدمتها، وما تعذر إنجازه.
- لا تعرض التفكير الداخلي التفصيلي.
''';

        _activeSubagentIds.add(task.id);
        late final String output;
        try {
          output = (await _models.processInput(
            subagentPrompt,
            conversationId: isolatedConversationId,
            persistTurn: false,
            allowedTools: allowedTools,
            shouldCancel: () =>
                _cancellationRequested || isTaskCancelled(),
            requestId: requestId,
            taskId: task.id,
            agentType: task.agentType,
          )).trim();
        } finally {
          _activeSubagentIds.remove(task.id);
        }

        if (_cancellationRequested || _isCancelledOutput(output)) {
          throw const SubagentInterrupted('تم إيقاف الوكيل الفرعي أثناء التنفيذ.');
        }
        if (_isIncompleteOutput(output)) {
          throw SubagentInterrupted(output);
        }
        if (_isFailureOutput(output)) {
          throw StateError(output.isEmpty
              ? 'The subagent runtime returned an empty response.'
              : output);
        }
        return output;
      },
    );

    _activeSubagentOrchestrator = orchestrator;
    var results = <SubagentResult>[];
    try {
      results = await orchestrator.run(tasks);

      // One bounded repair cycle lets the coordinator adapt to worker evidence
      // without creating an unbounded agent loop or replaying completed work.
      final hasRecoverableGaps = results.any((result) =>
          result.status == 'failed' || result.status == 'skipped');
      if (!_cancellationRequested && hasRecoverableGaps) {
        _emit(
          requestId: requestId,
          type: 'replanning_started',
          title: 'يراجع الوكيل الرئيسي فجوات التنفيذ ويخطط لمحاولة تصحيح واحدة',
          status: 'running',
          details: 'يسمح النظام بجولة تصحيح واحدة فقط؛ ولا يعيد تشغيل المهام المكتملة تلقائياً.',
        );
        try {
          final priorEvidence = results.map((result) {
            final task = tasks.firstWhere((item) => item.id == result.taskId);
            return 'الوكيل: ${task.agentType}\\nالمهمة: ${task.prompt}\\nالحالة: ${result.status}\\nالنتيجة: ${result.output ?? result.error ?? 'لا توجد نتيجة.'}';
          }).join('\\n---\\n');
          final repairPlan = await _models.generateStructuredOutput(
            '''
أنت منسق إصلاح لمهمة لم تكتمل بالكامل.
المهمة الأصلية: $prompt

نتائج الجولة السابقة:
$priorEvidence

أنشئ خطة تصحيح محدودة من 2 إلى 6 مهام JSON داخل الكائن {"tasks":[...]}. 
كل مهمة تحتوي id وrole وtitle وprompt وdepends_on.
استخدم فقط الأدوار explore أو plan أو coder أو reviewer.
لا تكرر أي مهمة اكتملت، ولا تعِد تنفيذ تغييرات ناجحة. افحص الحالة الحالية قبل اقتراح تعديل جديد.
عالج الفشل والفجوات فقط، واجعل المهام مستقلة قدر الإمكان. لا تذكر التفكير الداخلي.
''',
            conversationId: '$conversationId::replanner::$requestId',
            shouldCancel: () => _cancellationRequested,
          );
          if (!_cancellationRequested &&
              !repairPlan.startsWith('تم إيقاف التخطيط')) {
            final repairTasks = _parseSubagentPlan(
              repairPlan,
              requestId: '${requestId}_replan_1',
              allowCoder: isSoftwareTask,
            );
            tasks.addAll(repairTasks);
            final repairResults = await orchestrator.run(repairTasks);
            results = <SubagentResult>[...results, ...repairResults];
            _emit(
              requestId: requestId,
              type: 'replanning_completed',
              title: 'اكتملت جولة التصحيح المحدودة',
              status: 'completed',
              details: 'أضيفت ${repairTasks.length} مهام تصحيح دون إعادة تشغيل المهام المكتملة.',
            );
          }
        } catch (error) {
          _emit(
            requestId: requestId,
            type: 'replanning_failed',
            title: 'تعذر إنشاء خطة تصحيح آمنة',
            status: 'failed',
            details: error.toString(),
          );
          // Preserve the first-round evidence and continue with an honest partial result.
        }
      }
    } finally {
      if (identical(_activeSubagentOrchestrator, orchestrator)) {
        _activeSubagentOrchestrator = null;
      }
    }

    if (_cancellationRequested ||
        results.any((result) =>
            result.status == 'cancelled' || result.status == 'interrupted')) {
      return 'تم إيقاف المهمة قبل اكتمال جميع الوكلاء الفرعيين. اكتملت ${results.where((result) => result.status == 'completed').length} من ${results.length} مهام.';
    }

    final completed = results.where((result) => result.status == 'completed').toList();
    if (completed.isEmpty) {
      final failures = results
          .where((result) => result.status == 'failed')
          .map((result) => '${result.taskId}: ${result.error}')
          .join('\n');
      throw StateError('لم يتمكن أي وكيل فرعي من إكمال المهمة. $failures');
    }

    _emit(
      requestId: requestId,
      type: 'subagent_collection_completed',
      title: 'تم جمع نتائج الوكلاء الفرعيين',
      status: 'completed',
      details: 'نجح ${completed.length} من ${results.length} وكلاء؛ الفاشل والمتجاوز موضح في سجل المهمة.',
    );

    _emit(
      requestId: requestId,
      eventId: 'kernel_${requestId}_synthesis',
      type: 'synthesis_started',
      title: 'يراجع الوكيل الرئيسي النتائج ويعد الإجابة النهائية',
      status: 'running',
    );

    final evidence = results.map((result) {
      final task = tasks.firstWhere((item) => item.id == result.taskId);
      return '''
الوكيل: ${task.agentType}
المهمة: ${task.prompt}
الحالة: ${result.status}
النتيجة:
${result.output ?? result.error ?? 'لم تُنتج نتيجة.'}
''';
    }).join('\n---\n');

    final finalOutput = await _models.processInput(
      '''
المهمة الأصلية: $prompt

نتائج الوكلاء الفرعيين:
$evidence

اكتب الإجابة النهائية اعتماداً على النتائج أعلاه فقط.
إذا بقيت فجوة جوهرية لا يمكن حسمها من الأدلة، يمكنك تنفيذ جولة ديناميكية محدودة عبر create_subagent ثم spawn_subagent، مع check_subagent_status عند الحاجة. لا تتجاوز ستة وكلاء إضافيين، ولا تكرر عملاً مكتملًا.
يمكنك استخدام web_search للتحقق من معلومة خارجية فقط عند الحاجة، وask_user فقط إذا كان القرار لا يمكن استنتاجه بأمان.
لا تنفذ تعديلات مباشرة على الملفات في مرحلة التجميع؛ التعديلات البرمجية مسؤولية الوكلاء المصرح لهم في خطة التنفيذ.
ميّز بوضوح بين ما نُفذ فعلياً وما فشل أو تم تجاوزه أو لم يمكن التحقق منه.
إذا بقيت مهام فاشلة، قدم نتيجة جزئية مع بيان الفجوات ولا تصف المهمة بأنها مكتملة بالكامل.
''',
      conversationId: conversationId,
      persistTurn: false,
      allowedTools: const <String>{
        'ipython',
        'reset_ipython',
        'task',
        'dmail',
        'show_widget',
        'create_subagent',
        'spawn_subagent',
        'delete_subagent',
        'check_subagent_status',
        'send_message',
        'wait_for_message',
        'ask_user',
        'update_goal',
        'web_search',
        'lbs_tool',
        'fetch_urls',
        'visit',
        'click',
        'input',
        'find',
        'scrollup',
        'scrolldown',
        'browser_visit',
        'browser_click',
        'browser_find',
        'browser_input',
        'browser_state',
        'browser_scroll_up',
        'browser_scroll_down',
        'image_search',
        'search_image_by_text',
        'search_image_by_image',
        'generate_image',
        'edit_image',
        'generate_sound_effects',
        'find_asset_bbox',
        'crop_and_replicate_assets_in_image',
      },
      requestId: requestId,
      shouldCancel: () => _cancellationRequested,
    );
    final normalizedFinal = finalOutput.trim();
    if (_cancellationRequested ||
        _isCancelledOutput(normalizedFinal) ||
        _isIncompleteOutput(normalizedFinal)) {
      _emit(
        requestId: requestId,
        eventId: 'kernel_${requestId}_synthesis',
        type: 'synthesis_interrupted',
        title: 'توقف إعداد الإجابة النهائية',
        status: 'interrupted',
        details: normalizedFinal,
      );
      return normalizedFinal;
    }
    if (_isFailureOutput(normalizedFinal)) {
      _emit(
        requestId: requestId,
        eventId: 'kernel_${requestId}_synthesis',
        type: 'synthesis_failed',
        title: 'تعذر إعداد الإجابة النهائية',
        status: 'failed',
        details: normalizedFinal,
      );
      throw StateError(normalizedFinal);
    }

    await AgentMemoryService.instance.saveTurn(
      prompt,
      normalizedFinal,
      conversationId: conversationId,
    );
    _emit(
      requestId: requestId,
      eventId: 'kernel_${requestId}_synthesis',
      type: 'synthesis_completed',
      title: 'اكتملت مراجعة النتائج',
      status: 'completed',
      details: 'تم إعداد الإجابة النهائية من مخرجات الوكلاء المسجلة.',
    );
    return normalizedFinal;
  }

  List<SubagentTask> _parseSubagentPlan(
    String raw, {
    required String requestId,
    required bool allowCoder,
  }) {
    final start = raw.indexOf('{');
    if (start < 0) throw const FormatException('Planner returned no JSON object.');
    var depth = 0;
    var inString = false;
    var escaped = false;
    var end = -1;
    for (var index = start; index < raw.length; index++) {
      final character = raw[index];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (character == String.fromCharCode(92)) {
          escaped = true;
        } else if (character == '"') {
          inString = false;
        }
        continue;
      }
      if (character == '"') {
        inString = true;
      } else if (character == '{') {
        depth++;
      } else if (character == '}') {
        depth--;
        if (depth == 0) {
          end = index;
          break;
        }
      }
    }
    if (end < 0) throw const FormatException('Planner JSON object is incomplete.');
    final decoded = jsonDecode(raw.substring(start, end + 1));
    if (decoded is! Map || decoded['tasks'] is! List) {
      throw const FormatException('Planner JSON must contain a tasks array.');
    }
    final rawTasks = decoded['tasks'] as List;
    if (rawTasks.length < 2 || rawTasks.length > 6) {
      throw const FormatException('Planner must return between 2 and 6 tasks.');
    }

    final tasks = <SubagentTask>[];
    final localIds = <String>{};
    for (final item in rawTasks) {
      if (item is! Map) throw const FormatException('Invalid task object.');
      final id = item['id']?.toString().trim() ?? '';
      final role = item['role']?.toString().trim().toLowerCase() ?? '';
      final title = item['title']?.toString().trim() ?? '';
      final taskPrompt = item['prompt']?.toString().trim() ?? '';
      if (!RegExp(r'^[a-zA-Z0-9_-]{1,48}$').hasMatch(id) ||
          !localIds.add(id) ||
          title.isEmpty ||
          title.length > 100 ||
          taskPrompt.isEmpty ||
          taskPrompt.length > 1200) {
        throw const FormatException('Planner task fields are invalid.');
      }
      if (!const {'explore', 'plan', 'coder', 'reviewer'}.contains(role) ||
          (role == 'coder' && !allowCoder)) {
        throw const FormatException('Planner selected a disallowed agent role.');
      }
      final rawDependencies = item['depends_on'] ?? const <dynamic>[];
      if (rawDependencies is! List ||
          rawDependencies.any((dependency) => dependency is! String)) {
        throw const FormatException('Task dependencies must be a string list.');
      }
      final dependencies = rawDependencies
          .map((dependency) => dependency.toString().trim())
          .toList(growable: false);
      if (dependencies.toSet().length != dependencies.length) {
        throw const FormatException('Duplicate task dependency.');
      }
      tasks.add(SubagentTask(
        id: '${requestId}_agent_$id',
        title: 'الوكيل $role — $title',
        prompt: taskPrompt,
        agentType: role,
        dependsOn: dependencies
            .map((dependency) => '${requestId}_agent_$dependency')
            .toList(growable: false),
      ));
    }

    if (allowCoder && !tasks.any((task) => task.agentType == 'coder')) {
      throw const FormatException('Software plans must include an implementation agent.');
    }

    final ids = tasks.map((task) => task.id).toSet();
    for (final task in tasks) {
      if (task.dependsOn.any((dependency) => !ids.contains(dependency)) ||
          task.dependsOn.contains(task.id)) {
        throw const FormatException('Planner produced an invalid dependency graph.');
      }
    }
    final visited = <String>{};
    final visiting = <String>{};
    void visit(String id) {
      if (visiting.contains(id)) {
        throw const FormatException('Planner produced a dependency cycle.');
      }
      if (visited.contains(id)) return;
      visiting.add(id);
      for (final dependency in tasks.firstWhere((task) => task.id == id).dependsOn) {
        visit(dependency);
      }
      visiting.remove(id);
      visited.add(id);
    }
    for (final task in tasks) {
      visit(task.id);
    }
    return tasks;
  }

  List<SubagentTask> _fallbackSubagentPlan(
    String prompt, {
    required String requestId,
    required bool allowCoder,
  }) {
    final plan = _planner.createPlan(prompt);
    final tasks = <SubagentTask>[];
    for (var index = 0; index < plan.length; index++) {
      final number = plan[index]['step'] as int;
      final role = allowCoder
          ? switch (index) {
              0 || 1 => 'explore',
              2 => 'plan',
              3 => 'coder',
              _ => 'reviewer',
            }
          : switch (index) {
              0 || 1 => 'explore',
              2 => 'plan',
              _ => 'reviewer',
            };
      final dependencies = switch (index) {
        0 || 1 => const <String>[],
        2 => <String>['${requestId}_agent_1', '${requestId}_agent_2']
            .where((id) => tasks.any((task) => task.id == id))
            .toList(growable: false),
        _ => <String>['${requestId}_agent_${number - 1}'],
      };
      tasks.add(SubagentTask(
        id: '${requestId}_agent_$number',
        title: 'الوكيل $role — الخطوة $number',
        prompt: plan[index]['action'] as String,
        agentType: role,
        dependsOn: dependencies,
      ));
    }
    return tasks;
  }

  Future<bool> cancelSubagent(String taskId) async {
    final orchestrator = _activeSubagentOrchestrator;
    final scheduledChild = orchestrator != null && orchestrator.cancelTask(taskId);
    final recoveredChild = _activeSubagentIds.contains(taskId);
    if (!scheduledChild && !recoveredChild) return false;
    if (recoveredChild) _cancelledSubagentIds.add(taskId);
    _emit(
      requestId: _activeSubagentParentRequestId ?? _activeRequestId ?? 'runtime',
      taskId: taskId,
      type: 'subagent_cancellation_requested',
      title: 'طلب إيقاف الوكيل الفرعي',
      status: 'running',
    );
    if (recoveredChild) {
      try {
        await _models.cancelGeneration();
      } catch (_) {
        // The worker will observe its cancellation token at the next boundary.
      }
    }
    return true;
  }

  /// Rebuilds the parent answer after every interrupted child has been
  /// explicitly resumed. This is synthesis only; it cannot invoke tools.
  Future<String> synthesizeRecoveredRequest({
    required String requestId,
    required String prompt,
    required String conversationId,
    required List<Map<String, dynamic>> completedChildren,
  }) => _requestQueue.enqueue(() => _synthesizeRecoveredRequestAdmitted(
        requestId: requestId,
        prompt: prompt,
        conversationId: conversationId,
        completedChildren: completedChildren,
      ));

  Future<String> _synthesizeRecoveredRequestAdmitted({
    required String requestId,
    required String prompt,
    required String conversationId,
    required List<Map<String, dynamic>> completedChildren,
  }) async {
    if (prompt.trim().isEmpty || completedChildren.isEmpty ||
        completedChildren.any((child) => child['status'] != 'completed' ||
            (child['last_result']?.toString() ?? '').trim().isEmpty)) {
      throw StateError('لا يمكن إعادة تجميع المهمة قبل اكتمال جميع الوكلاء ونتائجهم.');
    }
    final executionId = 'recovered_synthesis_${requestId}_${DateTime.now().microsecondsSinceEpoch}';
    _activeRequestId = executionId;
    _cancellationRequested = false;
    _models.beginAgentRequest(executionId);
    _state = AgentKernelState.executing;
    try {
      final evidence = completedChildren.map((child) {
        final output = child['last_result']?.toString() ?? '';
        final bounded = output.length > 9000 ? '${output.substring(0, 9000)}…' : output;
        return '''
الوكيل: ${child['agent_type'] ?? 'unknown'}
المهمة: ${child['title'] ?? child['id']}
المعرّف: ${child['id']}
النتيجة الكاملة المحفوظة:
$bounded
''';
      }).join('\n---\n');
      _emit(
        requestId: requestId,
        type: 'recovered_synthesis_started',
        title: 'يعيد تجميع المهمة من نتائج الوكلاء المستعادة',
        status: 'running',
        details: 'اكتملت جميع الوكلاء؛ يعاد الآن بناء الإجابة النهائية دون إعادة تنفيذ أدوات.',
      );
      final output = (await _models.processInput(
        '''
المهمة الأصلية: $prompt

النتائج المحفوظة والمستعادة للوكلاء:
$evidence

اكتب نتيجة نهائية موحدة ومتماسكة اعتماداً على النتائج أعلاه فقط.
لا تنفذ أدوات ولا تنشئ أو تعدّل ملفات في مرحلة التجميع.
لا تضف حقائق أو نتائج غير موجودة في الأدلة.
اذكر أي قيود أو نقاط لم يتم التحقق منها، ولا تعرض التفكير الداخلي.
''',
        conversationId: conversationId,
        persistTurn: false,
        allowedTools: const <String>{},
        requestId: requestId,
        shouldCancel: () => _cancellationRequested,
      )).trim();
      if (_cancellationRequested || _isCancelledOutput(output) || _isIncompleteOutput(output)) {
        throw SubagentInterrupted(output.isEmpty ? 'توقف تجميع المهمة المستعادة.' : output);
      }
      if (_isFailureOutput(output)) throw StateError(output);
      _emit(
        requestId: requestId,
        type: 'recovered_synthesis_completed',
        title: 'اكتمل تجميع المهمة المستعادة',
        status: 'completed',
        details: output.length > 1400 ? '${output.substring(0, 1400)}…' : output,
        result: output,
      );
      return output;
    } finally {
      _models.endAgentRequest(executionId);
      _activeRequestId = null;
      _cancellationRequested = false;
      _state = AgentKernelState.idle;
    }
  }

  Future<bool> cancel() async {
    if (!isExecuting) return false;
    final requestId = _activeSubagentParentRequestId ?? _activeRequestId ?? 'runtime';
    _cancellationRequested = true;
    _activeSubagentOrchestrator?.cancel();
    _state = AgentKernelState.cancelling;
    _emit(
      requestId: requestId,
      eventId: 'kernel_${requestId}_cancellation',
      type: 'cancellation_requested',
      title: 'طلب إيقاف التنفيذ',
      status: 'running',
    );

    var accepted = false;
    try {
      accepted = await _models.cancelGeneration();
    } catch (_) {
      // The orchestrator still stops at the next safe boundary.
    }
    _emit(
      requestId: requestId,
      eventId: 'kernel_${requestId}_cancellation',
      type: 'cancellation_recorded',
      title: 'تم تسجيل طلب الإيقاف',
      status: 'completed',
      details: accepted
          ? 'قبل محرك الاستدلال إيقاف التوليد.'
          : 'سيوقف المنسق الخطوات التالية عند أقرب نقطة آمنة.',
    );
    return true;
  }

  Future<Map<String, dynamic>> exportWorkspace() =>
      _models.exportWorkspace();

  Future<List<String>> listWorkspaceFiles() =>
      _models.listWorkspaceFiles();
}
