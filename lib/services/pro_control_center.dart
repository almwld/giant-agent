import 'dart:async';

import 'package:flutter/foundation.dart';

import '../agent/task_manager.dart';
import '../agent/architecture/agent_event_bus.dart';
import '../domain/kernel/agent_observability.dart';
import '../domain/kernel/agent_kernel_store.dart';
import '../domain/mcp/mcp_client.dart';
import 'agent_service.dart';

/// Process-wide read model for the AgentsOS control center.
///
/// Every screen observes projections of the existing AgentService,
/// TaskManager and MCP client. This controller owns no database, queue,
/// model, executor or integration client of its own.
class ProControlCenter extends ChangeNotifier {
  ProControlCenter._();
  static final ProControlCenter instance = ProControlCenter._();

  final AgentService _agent = AgentService.instance;
  final TaskManager _tasks = TaskManager();

  AgentObservabilitySummary? metrics;
  List<AgentObservabilityEvent> recentEvents = const [];
  List<Map<String, dynamic>> tasks = const [];
  List<Map<String, dynamic>> agents = const [];
  List<McpServerConfig> integrations = const [];
  bool loading = false;
  Object? lastError;
  DateTime? lastUpdated;

  Future<void>? _inFlight;
  StreamSubscription<Map<String, dynamic>>? _eventSubscription;
  Timer? _refreshDebounce;

  Future<void> initialize() => refresh();

  void _listenForRuntimeChanges() {
    if (_eventSubscription != null) return;
    _eventSubscription = AgentEventBus.instance.events.listen((event) {
      if (event['type'] == 'stream_token') return;
      _refreshDebounce?.cancel();
      _refreshDebounce = Timer(const Duration(milliseconds: 350), () {
        unawaited(refresh().catchError((Object _) {}));
      });
    });
  }

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
      await _tasks.refreshFromStore();
      _listenForRuntimeChanges();
      final results = await Future.wait<Object>([
        _agent.observabilitySummaryForConversation('global'),
        _agent.mcpServers(),
        _agent.observabilityEventsForConversation('global', limit: 20),
      ]);
      metrics = results[0] as AgentObservabilitySummary;
      integrations = results[1] as List<McpServerConfig>;
      recentEvents = (results[2] as AgentObservabilityPage).events;
      tasks = _tasks.getTasks();

      // Fleet scope is global to AgentsOS, not limited to the special
      // "global" conversation. Use the same durable task projection.
      agents = tasks
          .where((task) =>
              task['kind'] == 'subagent' && task['is_dismissed'] != true)
          .map((task) => Map<String, dynamic>.unmodifiable(task))
          .toList(growable: false);
      lastUpdated = DateTime.now();
    } catch (error) {
      lastError = error;
      rethrow;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> createTask(String description) async {
    if (_tasks.isExecuting || isTaskExecuting) {
      throw StateError('أوقف المهمة النشطة أو انتظر اكتمالها قبل بدء مهمة أخرى.');
    }
    await _agent.initialize();
    final task = await _tasks.createTask(description);
    await refresh();
    return task;
  }

  Future<Map<String, dynamic>> startTask(String taskId) async {
    await _agent.initialize();
    final selected = await _tasks.selectTask(taskId);
    if (!selected) {
      throw StateError('تعذر تحديد المهمة؛ قد تكون هناك مهمة أخرى قيد التنفيذ.');
    }
    try {
      final result = await _tasks.executeNextStep();
      await refresh();
      return result;
    } catch (_) {
      await refresh();
      rethrow;
    }
  }

  Future<List<KernelEventRecord>> eventsForAgent(String taskId) =>
      _agent.eventsForSubagent(taskId);

  Future<bool> cancelAgent(String taskId) async {
    final accepted = await _agent.cancelSubagent(taskId);
    await refresh();
    return accepted;
  }

  Future<String> resumeAgent(
    String taskId, {
    required String sideEffectDisposition,
  }) async {
    final result = await _agent.resumeSubagent(
      taskId,
      sideEffectDisposition: sideEffectDisposition,
    );
    await refresh();
    return result;
  }

  Future<bool> dismissAgent(String taskId) async {
    final accepted = await _agent.dismissSubagent(taskId);
    await refresh();
    return accepted;
  }

  bool get isTaskExecuting => tasks.any((task) => task['status'] == 'running');

  Future<bool> cancelCurrentTask() async {
    final accepted = await _tasks.cancelTask();
    await refresh();
    return accepted;
  }

  Future<Map<String, dynamic>> resumeTask(String taskId) async {
    final result = await _tasks.resumeTask(taskId);
    await refresh();
    return result;
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    _eventSubscription?.cancel();
    super.dispose();
  }
}
