import 'dart:async';
import 'dart:convert';

import '../../services/agent_memory_service.dart';
import '../../services/model_service.dart';
import '../../services/openai_compatible_provider.dart';
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
    String? eventId,
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
      final openRouterEnabled = await OpenAICompatibleProvider.instance.isEnabled();
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


  bool _isCancelledOutput(String output) =>
      output.startsWith('تم إيقاف المهمة') ||
      output.startsWith('تم إيقاف تنفيذ الوكيل') ||
      output.startsWith('تم إيقاف الوكيل بعد اكتمال الأداة') ||
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
      return _models.processInput(prompt, conversationId: conversationId);
    }

    final plan = _planner.createPlan(prompt);
    final tasks = <SubagentTask>[];
    for (var index = 0; index < plan.length; index++) {
      final step = plan[index];
      final number = step['step'] as int;
      final role = switch (index) {
        0 || 1 => 'explore',
        2 => 'plan',
        3 => 'coder',
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
        prompt: step['action'] as String,
        agentType: role,
        dependsOn: dependencies,
      ));
    }

    _emit(
      requestId: requestId,
      type: 'plan_created',
      title: 'تم إنشاء خطة وتوزيعها على وكلاء فرعيين',
      status: 'completed',
      details: jsonEncode(tasks.map((task) => <String, Object?>{
        'task_id': task.id,
        'agent_type': task.agentType,
        'title': task.title,
        'depends_on': task.dependsOn,
      }).toList()),
    );

    final orchestrator = SubagentOrchestrator(
      parentRequestId: requestId,
      conversationId: conversationId,
      // The current llama.cpp JNI context is mutable and protected by one FIFO
      // lock. Keep one inference worker until the runtime supports isolated
      // parallel contexts; task state and dependency scheduling are independent.
      maxConcurrency: 1,
      onEvent: (event) {
        final taskId = event['task_id']?.toString() ?? '';
        _emit(
          requestId: requestId,
          eventId: taskId,
          type: event['type']?.toString() ?? 'subagent_event',
          title: event['title']?.toString() ?? 'تحديث الوكيل الفرعي',
          status: event['status']?.toString() ?? 'pending',
          details: event['details']?.toString(),
        );
      },
      execute: (task, dependencyResults) async {
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
            const <String>{'read_file', 'list_files'},
          'coder' => const <String>{
              'create_file',
              'read_file',
              'write_file',
              'list_files',
              'execute_python',
              'gain_terminal',
            },
          _ => const <String>{'read_file', 'list_files'},
        };

        final isolatedConversationId =
            '${conversationId}::subagent::${task.id}';
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

        final output = (await _models.processInput(
          subagentPrompt,
          conversationId: isolatedConversationId,
          persistTurn: false,
          allowedTools: allowedTools,
        )).trim();

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
    late final List<SubagentResult> results;
    try {
      results = await orchestrator.run(tasks);
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
لا تنفذ أدوات جديدة في هذه المرحلة، ولا تضف نتائج غير موجودة.
ميّز بوضوح بين ما نُفذ فعلياً وما فشل أو تم تجاوزه أو لم يمكن التحقق منه.
إذا كانت بعض المهام فاشلة، قدم نتيجة جزئية مع بيان الفجوات ولا تصف المهمة بأنها مكتملة بالكامل.
''',
      conversationId: conversationId,
      persistTurn: false,
      allowedTools: const <String>{},
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

  Future<bool> cancel() async {
    if (!isExecuting) return false;
    final requestId = _activeRequestId ?? 'runtime';
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
