import 'package:flutter/foundation.dart';

import '../agent/task_manager.dart';
import '../domain/kernel/agent_observability.dart';
import '../domain/mcp/mcp_client.dart';
import '../services/agent_service.dart';

/// Process-wide read model for the AgentsOS control center.
///
/// All screens observe projections of the existing AgentService and
/// TaskManager. This class deliberately owns no database, queue, model,
/// executor, or MCP client of its own.
class ProControlCenter extends ChangeNotifier {
  ProControlCenter._();
  static final ProControlCenter instance = ProControlCenter._();

  final AgentService _agent = AgentService.instance;
  final TaskManager _tasks = TaskManager();

  AgentObservabilitySummary? metrics;
  List<Map<String, dynamic>> tasks = const [];
  List<Map<String, dynamic>> agents = const [];
  List<McpServerConfig> integrations = const [];
  bool loading = false;
  Object? lastError;
  DateTime? lastUpdated;

  Future<void>? _inFlight;

  Future<void> initialize() => refresh();

  Future<void> refresh() {
    final active = _inFlight;
    if (active != null) return active;
    late final Future<void> operation;
    operation = _refresh().whenComplete(() {
      if (identical(_inFlight, operation)) _inFlight = null;
    });
    _inFlight = operation;
    return operation;
  }

  Future<void> _refresh() async {
    loading = true;
    lastError = null;
    notifyListeners();
    try {
      await _agent.initialize();
      await _tasks.initialize();
      final results = await Future.wait<Object>([
        _agent.observabilitySummaryForConversation('global'),
        _agent.subagentsForConversation('global'),
        _agent.mcpServers(),
      ]);
      metrics = results[0] as AgentObservabilitySummary;
      agents = results[1] as List<Map<String, dynamic>>;
      integrations = results[2] as List<McpServerConfig>;
      tasks = _tasks.getTasks();
      lastUpdated = DateTime.now();
    } catch (error) {
      lastError = error;
      rethrow;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> cancelAgent(String taskId) async {
    final accepted = await _agent.cancelSubagent(taskId);
    await refresh();
    return accepted;
  }

  Future<bool> dismissAgent(String taskId) async {
    final accepted = await _agent.dismissSubagent(taskId);
    await refresh();
    return accepted;
  }

  Future<bool> cancelCurrentTask() async {
    final accepted = await _tasks.cancelTask();
    await refresh();
    return accepted;
  }
}
