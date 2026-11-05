import 'dart:async';
import 'dart:convert';

import '../../services/model_service.dart';
import '../../services/planner_service.dart';
import 'agent_timeline_event.dart';

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

  AgentKernelState get state => _state;
  String? get activeRequestId => _activeRequestId;
  Stream<AgentTimelineEvent> get events => _events.stream;

  bool get isExecuting =>
      _activeRequestId != null ||
      _state == AgentKernelState.executing ||
      _state == AgentKernelState.cancelling;

  void _emit({
    required String requestId,
    required String type,
    required String title,
    required String status,
    String? details,
  }) {
    _events.add(AgentTimelineEvent(
      id: 'kernel_${requestId}_${++_eventSequence}',
      requestId: requestId,
      type: type,
      title: title,
      status: status,
      timestamp: DateTime.now(),
      details: details,
    ));
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
      type: 'runtime_initializing',
      title: 'تهيئة محرك الوكيل',
      status: 'running',
    );
    try {
      await _models.init();
      _state = AgentKernelState.idle;
      _emit(
        requestId: 'runtime',
        type: 'runtime_ready',
        title: 'محرك الوكيل جاهز',
        status: 'completed',
        details: 'اكتملت تهيئة مكتبة النماذج المحلية.',
      );
    } catch (error) {
      _state = AgentKernelState.failed;
      _emit(
        requestId: 'runtime',
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

  Future<AgentResponse> execute(AgentRequest request) async {
    final prompt = request.prompt.trim();
    if (prompt.isEmpty) {
      throw ArgumentError.value(
        request.prompt,
        'prompt',
        'Task must not be empty.',
      );
    }
    if (isExecuting) {
      throw StateError('An agent request is already executing.');
    }

    // Reserve the execution slot before the first await so two requests cannot
    // both pass admission while native model readiness is being checked.
    _activeRequestId = request.id;
    _cancellationRequested = false;
    _emit(
      requestId: request.id,
      type: 'request_received',
      title: 'تم استلام الطلب',
      status: 'completed',
    );

    try {
      if (!_models.hasActiveModel()) {
        throw StateError('Load a local GGUF model before starting an agent task.');
      }

      final nativeModelLoaded = await _models.isModelLoaded();
      if (!nativeModelLoaded) {
        throw StateError(
          'The selected GGUF model is not loaded in the native runtime.',
        );
      }

      _emit(
        requestId: request.id,
        type: 'model_ready',
        title: 'تم التحقق من جاهزية النموذج المحلي',
        status: 'completed',
      );

      _state = AgentKernelState.executing;
      _emit(
        requestId: request.id,
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
      final wasCancelled =
          normalizedOutput.startsWith('تم إيقاف تنفيذ الوكيل') ||
          normalizedOutput.startsWith('تم إيقاف الوكيل بعد اكتمال الأداة') ||
          normalizedOutput.startsWith('تم إيقاف التوليد') ||
          normalizedOutput.contains('[تم إيقاف التوليد]');
      final executionWasBounded =
          normalizedOutput.startsWith('وصل الوكيل إلى الحد الآمن') ||
          normalizedOutput.startsWith('أوقف الوكيل تكرار استدعاء الأداة');

      if (wasCancelled || executionWasBounded) {
        _state = AgentKernelState.idle;
        _emit(
          requestId: request.id,
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
      if (normalizedOutput.isEmpty ||
          normalizedOutput.startsWith('ERROR:') ||
          normalizedOutput.startsWith('تعذر تشغيل النموذج المحلي:') ||
          normalizedOutput.startsWith('تعذر تحليل استدعاء الأداة أو تنفيذه:') ||
          normalizedOutput.startsWith('⚠️ استورد نموذج')) {
        throw StateError(
          normalizedOutput.isEmpty
              ? 'The local model returned an empty response.'
              : normalizedOutput,
        );
      }

      _state = AgentKernelState.idle;
      _emit(
        requestId: request.id,
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
        type: 'execution_failed',
        title: 'تعذر إكمال الطلب',
        status: 'failed',
        details: error.toString(),
      );
      rethrow;
    } finally {
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
    _emit(
      requestId: requestId,
      type: 'plan_created',
      title: 'تم إنشاء خطة تنفيذ منظمة',
      status: 'completed',
      details: jsonEncode(plan),
    );

    final results = <Map<String, String>>[];
    for (final step in plan) {
      if (_cancellationRequested) {
        return 'تم إيقاف المهمة بعد ${results.length} من ${plan.length} خطوات.';
      }

      final number = step['step'] as int;
      final action = step['action'] as String;
      _emit(
        requestId: requestId,
        type: 'step_started',
        title: 'الخطوة $number: $action',
        status: 'running',
        details: 'بدأ تنفيذ الخطوة بواسطة النموذج المحلي والأدوات المتاحة.',
      );

      final previous = results.isEmpty
          ? 'لا توجد نتائج سابقة.'
          : results
              .map((item) =>
                  'الخطوة: ${item['action']}\nالنتيجة: ${item['result']}')
              .join('\n\n');
      final stepPrompt = '''
المهمة الأصلية:
$prompt

الخطة:
${plan.map((item) => '${item['step']}. ${item['action']}').join('\n')}

الخطوة الحالية ($number/${plan.length}):
$action

نتائج الخطوات السابقة:
$previous

نفّذ هذه الخطوة فقط. لا تكرر التخطيط ولا تنفذ الخطوات اللاحقة.
استخدم الأدوات المحلية عند الحاجة. لا تدّع نجاح أي تعديل أو تشغيل دون نتيجة أداة فعلية.
أعد نتيجة هذه الخطوة بوضوح، واذكر ما تعذر تنفيذه.
''';

      final output = (await _models.processInput(
        stepPrompt,
        conversationId: conversationId,
      )).trim();

      if (_cancellationRequested || _isCancelledOutput(output) ||
          _isIncompleteOutput(output)) {
        return output;
      }
      if (_isFailureOutput(output)) {
        _emit(
          requestId: requestId,
          type: 'step_failed',
          title: 'فشلت الخطوة $number',
          status: 'failed',
          details: output,
        );
        throw StateError(output.isEmpty
            ? 'The local model returned an empty step result.'
            : output);
      }

      results.add({'action': action, 'result': output});
      final visibleOutput =
          output.length > 1200 ? '${output.substring(0, 1200)}…' : output;
      _emit(
        requestId: requestId,
        type: 'step_completed',
        title: 'اكتملت الخطوة $number',
        status: 'completed',
        details: visibleOutput,
      );
    }

    if (_cancellationRequested) {
      return 'تم إيقاف المهمة قبل إعداد الإجابة النهائية.';
    }

    _emit(
      requestId: requestId,
      type: 'synthesis_started',
      title: 'مراجعة النتائج وإعداد الإجابة النهائية',
      status: 'running',
    );
    final evidence = results
        .asMap()
        .entries
        .map((entry) =>
            '${entry.key + 1}. ${entry.value['action']}\n${entry.value['result']}')
        .join('\n\n');
    return _models.processInput(
      '''
المهمة الأصلية: $prompt

نتائج التنفيذ:
$evidence

اكتب الإجابة النهائية اعتماداً على النتائج أعلاه فقط.
لا تنفذ أدوات جديدة في هذه المرحلة، ولا تضف نتائج غير موجودة.
ميّز بين ما تم تنفيذه فعلياً وما لم يكتمل أو لم يمكن التحقق منه.
''',
      conversationId: conversationId,
    );
  }

  Future<bool> cancel() async {
    if (!isExecuting) return false;
    final requestId = _activeRequestId ?? 'runtime';
    _cancellationRequested = true;
    _state = AgentKernelState.cancelling;
    _emit(
      requestId: requestId,
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
