import '../agent/architecture/agent_kernel.dart';
import '../agent/architecture/agent_timeline_event.dart';
import 'model_service.dart';

/// Public facade for task execution. All requests pass through AgentKernel,
/// which delegates to the single process-wide ModelService/LlamaService.
class AgentService {
  AgentService._();

  static final AgentService instance = AgentService._();

  final AgentKernel _kernel = AgentKernel.instance;
  final ModelService _models = ModelService();

  bool get isRunning => _kernel.isExecuting;

  Future<void> initialize() => _kernel.initialize();

  Future<String> runTask(String prompt, {String conversationId = 'global', String? requestId}) async {
    final request = AgentRequest(
      id: requestId ?? DateTime.now().microsecondsSinceEpoch.toString(),
      prompt: prompt,
      conversationId: conversationId,
    );
    _models.beginAgentRequest(request.id);
    try {
      final response = await _kernel.execute(request);
      return response.output;
    } finally {
      _models.endAgentRequest(request.id);
    }
  }

  Future<bool> cancel() => _kernel.cancel();

  Future<Map<String, dynamic>> exportWorkspace() => _kernel.exportWorkspace();

  Future<List<String>> listWorkspaceFiles() => _kernel.listWorkspaceFiles();

  /// Exposes the shared model facade for status and model-library screens.
  ModelService get modelService => _models;

  /// Lifecycle stream for workflow timelines and diagnostics.
  Stream<AgentTimelineEvent> get events => _kernel.events;
}
