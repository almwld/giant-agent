import 'model_service.dart';

/// Compatibility facade for callers that use the older AgentService API.
/// All responses and tool execution now go through the real local model runtime.
class AgentService {
  static final AgentService _instance = AgentService._internal();

  factory AgentService() => _instance;

  AgentService._internal();

  final ModelService _modelService = ModelService();

  Future<String> process(String input) {
    return _modelService.processInput(input);
  }
}
