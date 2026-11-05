import 'dart:async';

import '../../services/model_service.dart';
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
  final StreamController<AgentTimelineEvent> _events =
      StreamController<AgentTimelineEvent>.broadcast();

  AgentKernelState _state = AgentKernelState.idle;
  String? _activeRequestId;
  Future<void>? _initialization;
  int _eventSequence = 0;

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

      final output = await _models.processInput(
        prompt,
        conversationId: request.conversationId,
      );
      final normalizedOutput = output.trim();
      if (normalizedOutput.startsWith('تم إيقاف تنفيذ الوكيل') ||
          normalizedOutput.startsWith('تم إيقاف التوليد')) {
        _state = AgentKernelState.idle;
        _emit(
          requestId: request.id,
          type: 'execution_interrupted',
          title: 'توقف التنفيذ بطلب المستخدم',
          status: 'interrupted',
          details: 'أعاد المحرك المحلي حالة الإيقاف بدل إعلان اكتمال المهمة.',
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
      if (_state == AgentKernelState.failed ||
          _state == AgentKernelState.executing ||
          _state == AgentKernelState.cancelling) {
        _state = AgentKernelState.idle;
      }
    }
  }

  Future<bool> cancel() async {
    if (!isExecuting) return false;
    final requestId = _activeRequestId ?? 'runtime';
    _state = AgentKernelState.cancelling;
    _emit(
      requestId: requestId,
      type: 'cancellation_requested',
      title: 'طلب إيقاف التنفيذ',
      status: 'running',
    );

    final accepted = await _models.cancelGeneration();
    _emit(
      requestId: requestId,
      type: accepted ? 'cancellation_accepted' : 'cancellation_rejected',
      title: accepted ? 'تم قبول طلب الإيقاف' : 'لم يقبل المحرك طلب الإيقاف',
      status: accepted ? 'completed' : 'failed',
      details: accepted
          ? 'سيوقف المحرك التوليد عند نقطة الإلغاء الآمنة.'
          : 'لم يؤكد المحرك الأصلي قبول الإلغاء.',
    );
    if (!accepted) _state = AgentKernelState.executing;
    return accepted;
  }

  Future<Map<String, dynamic>> exportWorkspace() =>
      _models.exportWorkspace();

  Future<List<String>> listWorkspaceFiles() =>
      _models.listWorkspaceFiles();
}
