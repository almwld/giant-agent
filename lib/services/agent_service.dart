import 'dart:async';

import 'model_service.dart';

/// Public task facade. All inference and tool execution is delegated to the
/// single process-wide ModelService/LlamaService runtime.
class AgentService {
  AgentService._();
  static final AgentService instance = AgentService._();

  final ModelService _models = ModelService();
  bool _running = false;
  bool get isRunning => _running;

  Future<void> initialize() => _models.init();

  Future<String> runTask(String prompt) async {
    final normalized = prompt.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(prompt, 'prompt', 'Task must not be empty.');
    }
    if (_running) {
      throw StateError('An agent task is already running.');
    }
    if (!_models.hasActiveModel()) {
      throw StateError('Load a local GGUF model before starting an agent task.');
    }
    _running = true;
    try {
      return await _models.processInput(normalized);
    } finally {
      _running = false;
    }
  }

  Future<bool> cancel() => _models.cancelGeneration();

  Future<Map<String, dynamic>> exportWorkspace() => _models.exportWorkspace();

  Future<List<String>> listWorkspaceFiles() => _models.listWorkspaceFiles();
}
