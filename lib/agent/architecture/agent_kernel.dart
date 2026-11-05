import 'dart:async';

import '../../services/model_service.dart';

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

/// Structured lifecycle event for workflow UI, diagnostics and future observers.
class AgentKernelEvent {
  const AgentKernelEvent({
    required this.requestId,
    required this.state,
    required this.timestamp,
    this.message,
  });

  final String requestId;
  final AgentKernelState state;
  final DateTime timestamp;
  final String? message;
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

/// Central orchestration kernel for the local-first AI architecture.
///
/// The kernel coordinates request lifecycle and readiness while delegating
/// inference, memory retrieval and bounded tool execution to ModelService.
/// It deliberately does not invent a planner or cloud fallback: the active
/// GGUF model remains the source of generated responses.
class AgentKernel {
  AgentKernel._();

  static final AgentKernel instance = AgentKernel._();

  final ModelService _models = ModelService();
  final StreamController<AgentKernelEvent> _events =
      StreamController<AgentKernelEvent>.broadcast();

  AgentKernelState _state = AgentKernelState.idle;
  String? _activeRequestId;

  AgentKernelState get state => _state;
  String? get activeRequestId => _activeRequestId;
  Stream<AgentKernelEvent> get events => _events.stream;
  bool get isExecuting => _state == AgentKernelState.executing ||
      _state == AgentKernelState.cancelling;

  void _publish(AgentKernelState state, String requestId, [String? message]) {
    _state = state;
    _events.add(AgentKernelEvent(
      requestId: requestId,
      state: state,
      timestamp: DateTime.now(),
      message: message,
    ));
  }

  Future<void> initialize() async {
    if (_state == AgentKernelState.initializing) return;
    _publish(AgentKernelState.initializing, 'runtime');
    try {
      await _models.init();
      _publish(AgentKernelState.idle, 'runtime');
    } catch (error) {
      _publish(AgentKernelState.failed, 'runtime', error.toString());
      rethrow;
    }
  }

  Future<AgentResponse> execute(AgentRequest request) async {
    final prompt = request.prompt.trim();
    if (prompt.isEmpty) {
      throw ArgumentError.value(request.prompt, 'prompt', 'Task must not be empty.');
    }
    if (isExecuting) {
      throw StateError('An agent request is already executing.');
    }
    if (!_models.hasActiveModel()) {
      throw StateError('Load a local GGUF model before starting an agent task.');
    }

    _activeRequestId = request.id;
    _publish(AgentKernelState.executing, request.id);
    try {
      final output = await _models.processInput(
        prompt,
        conversationId: request.conversationId,
      );
      _publish(AgentKernelState.idle, request.id);
      return AgentResponse(
        requestId: request.id,
        output: output,
        completedAt: DateTime.now(),
      );
    } catch (error) {
      _publish(AgentKernelState.failed, request.id, error.toString());
      rethrow;
    } finally {
      _activeRequestId = null;
      if (_state == AgentKernelState.failed) {
        // Keep the failure event observable, then return the kernel to idle
        // so a later request can be accepted.
        _state = AgentKernelState.idle;
      }
    }
  }

  Future<bool> cancel() async {
    if (!isExecuting) return false;
    final requestId = _activeRequestId ?? 'runtime';
    _publish(AgentKernelState.cancelling, requestId);
    final accepted = await _models.cancelGeneration();
    if (!accepted) {
      _publish(AgentKernelState.executing, requestId,
          'Cancellation was not accepted by the native runtime.');
    }
    return accepted;
  }

  Future<Map<String, dynamic>> exportWorkspace() => _models.exportWorkspace();

  Future<List<String>> listWorkspaceFiles() => _models.listWorkspaceFiles();
}
