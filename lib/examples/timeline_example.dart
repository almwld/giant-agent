import 'dart:async';
import 'package:flutter/material.dart';

import '../core/timeline_engine.dart';
import '../core/tool_cancellation_manager.dart';
import '../data/timeline_database.dart';
import '../widgets/advanced_timeline_widget.dart';

/// Reference integration screen. In the real agent runtime, replace the demo
/// worker with the actual orchestrator/tool implementation and pass the same
/// cancellation token into the operation that performs the work.
class TimelineExampleScreen extends StatefulWidget {
  const TimelineExampleScreen({super.key});

  @override
  State<TimelineExampleScreen> createState() => _TimelineExampleScreenState();
}

class _TimelineExampleScreenState extends State<TimelineExampleScreen> {
  final _database = TimelineDatabase.instance;
  final _cancellations = ToolCancellationManager();
  TimelineEngine? _engine;
  TimelineSession? _session;
  StreamSubscription<AgentTimelineEvent>? _persistenceSubscription;
  bool _initializing = true;
  bool _disposed = false;
  String? _activeToolCallId;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final session = await _database.createSession(title: 'Agent run');
      final engine = TimelineEngine(sessionId: session.id);
      final subscription = engine.bus.stream.listen((event) async {
        try {
          await _database.saveEvent(event);
        } catch (error, stack) {
          FlutterError.reportError(FlutterErrorDetails(
            exception: error, stack: stack,
            library: 'timeline persistence',
            context: ErrorDescription('while saving timeline event'),
          ));
        }
      });
      if (_disposed) {
        await subscription.cancel();
        await engine.dispose();
        return;
      }
      setState(() {
        _session = session;
        _engine = engine;
        _persistenceSubscription = subscription;
        _initializing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _initializing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not initialize timeline: $error')),
      );
    }
  }

  Future<void> _runDemo() async {
    final engine = _engine;
    if (engine == null || engine.isRunning) return;

    final task = engine.add(
      type: TimelineEventType.taskStarted,
      title: 'Research task started',
      status: TimelineStatus.running,
      description: 'Demonstration of persisted, cancellable agent activity.',
    );
    final agentId = timelineNewId('agent');
    engine.add(
      type: TimelineEventType.agentCreated,
      title: 'Research agent created',
      status: TimelineStatus.completed,
      agentId: agentId,
      metadata: {'role': 'researcher'},
    );
    engine.add(
      type: TimelineEventType.agentStarted,
      title: 'Research agent running',
      status: TimelineStatus.running,
      agentId: agentId,
    );

    final toolCallId = timelineNewId('call');
    final token = _cancellations.registerTool(toolCallId);
    _activeToolCallId = toolCallId;
    final toolEvent = engine.add(
      type: TimelineEventType.toolStarted,
      title: 'Collecting source material',
      status: TimelineStatus.running,
      agentId: agentId,
      toolCallId: toolCallId,
      toolName: 'collect_sources',
      progress: 0,
    );

    try {
      // Demo worker: progress is emitted by the operation itself, not by a
      // background timer that fabricates progress independently.
      for (var step = 1; step <= 10; step++) {
        await token.delay(const Duration(milliseconds: 450));
        token.throwIfCancelled();
        engine.update(toolEvent.id, progress: step / 10);
      }
      engine.update(toolEvent.id, status: TimelineStatus.completed,
        progress: 1, completedAt: DateTime.now());
      engine.add(
        type: TimelineEventType.agentCompleted,
        title: 'Research agent completed',
        status: TimelineStatus.completed,
        agentId: agentId,
      );
      engine.update(task.id, status: TimelineStatus.completed,
        completedAt: DateTime.now());
    } on ToolCancelledException catch (error) {
      engine.update(toolEvent.id, status: TimelineStatus.cancelled,
        error: error.reason, completedAt: DateTime.now());
      engine.add(
        type: TimelineEventType.taskCancelled,
        title: 'Task cancelled',
        status: TimelineStatus.cancelled,
        error: error.reason,
      );
      engine.update(task.id, status: TimelineStatus.cancelled,
        error: error.reason, completedAt: DateTime.now());
    } catch (error) {
      engine.update(toolEvent.id, status: TimelineStatus.failed,
        error: error.toString(), completedAt: DateTime.now());
      engine.add(
        type: TimelineEventType.agentFailed,
        title: 'Research agent failed',
        status: TimelineStatus.failed,
        agentId: agentId,
        error: error.toString(),
      );
      engine.update(task.id, status: TimelineStatus.failed,
        error: error.toString(), completedAt: DateTime.now());
    } finally {
      _cancellations.unregisterTool(toolCallId, expected: token);
      if (_activeToolCallId == toolCallId) _activeToolCallId = null;
    }
  }

  Future<void> _cancelTool(String toolCallId) async {
    await _cancellations.cancelTool(toolCallId, reason: 'Stopped by user');
  }

  Future<void> _restoreSession() async {
    final session = _session;
    final engine = _engine;
    if (session == null || engine == null) return;
    final events = await _database.loadEvents(session.id);
    engine.restore(events);
  }

  @override
  void dispose() {
    _disposed = true;
    _persistenceSubscription?.cancel();
    _cancellations.dispose();
    _engine?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final engine = _engine;
    return Scaffold(
      backgroundColor: const Color(0xFF111113),
      appBar: AppBar(
        title: const Text('Agent timeline'),
        backgroundColor: const Color(0xFF111113),
        actions: [
          IconButton(
            tooltip: 'Restore saved events',
            onPressed: _restoreSession,
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      body: engine == null
          ? const Center(child: Text('Timeline unavailable'))
          : StreamBuilder<List<AgentTimelineEvent>>(
              stream: engine.changes,
              initialData: engine.events,
              builder: (context, snapshot) => ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  AdvancedTimelineWidget(
                    events: snapshot.data ?? const [],
                    onCancelTool: _cancelTool,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: engine.isRunning ? null : _runDemo,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Run cancellable demo'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Session: ${_session?.id ?? 'initializing'}',
                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                ],
              ),
            ),
    );
  }
}
