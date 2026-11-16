import 'package:flutter/material.dart';

import '../theme/pro_theme.dart';
import '../domain/kernel/agent_kernel_store.dart';
import '../services/pro_control_center.dart';
import '../widgets/pro_app_bar.dart';

/// Read-only detail projections for durable task and subagent records.
/// These widgets deliberately display only fields supplied by the canonical
/// runtime projection; they do not create a second source of truth.
class ProTaskDetailScreen extends StatelessWidget {
  const ProTaskDetailScreen({super.key, required this.task});

  final Map<String, dynamic> task;

  @override
  Widget build(BuildContext context) {
    final steps = task['steps'] is List ? task['steps'] as List : const [];
    return Scaffold(
      backgroundColor: ProTheme.bgDark,
      appBar: const ProAppBar(title: 'Task details'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _header(task['description']?.toString() ?? 'Task', task['status']?.toString() ?? 'unknown'),
          _section('Lifecycle', [
            _row('Task ID', task['id']),
            _row('Conversation', task['conversation_id']),
            _row('Created', task['created_at']),
            _row('Updated', task['updated_at']),
            _row('Started', task['started_at']),
            _row('Completed', task['completed_at']),
          ]),
          if (task['recovery_note'] != null)
            _section('Recovery review required', [
              Text(task['recovery_note'].toString(), style: const TextStyle(color: ProTheme.textPrimary)),
              const SizedBox(height: 8),
              const Text('Check external side effects before requesting resume.', style: TextStyle(color: ProTheme.textSecondary)),
            ]),
          if (task['error'] != null)
            _section('Failure', [SelectableText(task['error'].toString(), style: const TextStyle(color: ProTheme.dangerRed))]),
          if (task['result'] != null)
            _section('Result', [SelectableText(task['result'].toString(), style: const TextStyle(color: ProTheme.textPrimary))]),
          _section('Steps', steps.isEmpty
              ? [const Text('No step records are available.', style: TextStyle(color: ProTheme.textSecondary))]
              : steps.whereType<Map>().map((step) => _step(Map<String, dynamic>.from(step))).toList()),
          if ((task['id'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _openTaskEventHistory(context),
                  icon: const Icon(Icons.timeline),
                  label: const Text('Open persisted task lifecycle history'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openTaskEventHistory(BuildContext context) async {
    final taskId = task['id'].toString();
    try {
      final events = await ProControlCenter.instance.eventsForTask(taskId);
      if (!context.mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ProTaskEventHistoryScreen(
          taskTitle: task['description']?.toString() ?? taskId,
          events: events,
        ),
      ));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load task lifecycle history: $error')),
      );
    }
  }

  Widget _step(Map<String, dynamic> step) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Step ${step['step'] ?? '—'} · ${step['status'] ?? 'unknown'}',
          style: const TextStyle(color: ProTheme.neonGreen, fontWeight: FontWeight.bold)),
      if (step['action'] != null) Text(step['action'].toString(), style: const TextStyle(color: ProTheme.textPrimary)),
      if (step['result'] != null) SelectableText(step['result'].toString(), style: const TextStyle(color: ProTheme.textSecondary)),
      if (step['error'] != null) SelectableText(step['error'].toString(), style: const TextStyle(color: ProTheme.dangerRed)),
      if (step['recovery_state'] != null) Text('Recovery: ${step['recovery_state']}', style: const TextStyle(color: ProTheme.textSecondary)),
      const Divider(color: Colors.white12),
    ]),
  );
}

class ProTaskEventHistoryScreen extends StatelessWidget {
  const ProTaskEventHistoryScreen({
    super.key,
    required this.taskTitle,
    required this.events,
  });

  final String taskTitle;
  final List<KernelEventRecord> events;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: ProTheme.bgDark,
    appBar: ProAppBar(title: 'Task activity · $taskTitle'),
    body: events.isEmpty
        ? const Center(child: Text('No persisted task lifecycle events found.', style: TextStyle(color: ProTheme.textSecondary)))
        : ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: events.length,
            separatorBuilder: (_, __) => const Divider(color: Colors.white12),
            itemBuilder: (context, index) {
              final event = events[index];
              final failed = event.status == 'failed' || event.status == 'error';
              final completed = event.status == 'completed';
              return ListTile(
                leading: Icon(
                  failed ? Icons.error_outline : completed ? Icons.check_circle_outline : Icons.timeline,
                  color: failed ? ProTheme.dangerRed : completed ? ProTheme.neonGreen : ProTheme.textSecondary,
                ),
                title: Text(event.type.replaceAll('_', ' '), style: const TextStyle(color: ProTheme.textPrimary)),
                subtitle: Text(
                  '${event.status} • ${event.createdAt.toLocal()}',
                  style: const TextStyle(color: ProTheme.textSecondary, fontSize: 11),
                ),
              );
            },
          ),
  );
}

class ProAgentDetailScreen extends StatelessWidget {
  const ProAgentDetailScreen({super.key, required this.agent});

  final Map<String, dynamic> agent;

  @override
  Widget build(BuildContext context) {
    final entries = agent.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Scaffold(
      backgroundColor: ProTheme.bgDark,
      appBar: const ProAppBar(title: 'Agent details'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _header(
            agent['title']?.toString() ?? agent['agent_id']?.toString() ?? 'Subagent',
            agent['status']?.toString() ?? 'unknown',
          ),
          _section('Runtime record', entries.map((entry) => _row(entry.key, entry.value)).toList()),
          if ((agent['task_id'] ?? agent['id'])?.toString().isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _openEventHistory(context),
                  icon: const Icon(Icons.timeline),
                  label: const Text('Open persisted lifecycle history'),
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Values shown here come from the persisted subagent snapshot. Actions remain available from the fleet screen.',
              style: TextStyle(color: ProTheme.textSecondary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openEventHistory(BuildContext context) async {
    final taskId = (agent['task_id'] ?? agent['id']).toString();
    try {
      final events = await ProControlCenter.instance.eventsForAgent(taskId);
      if (!context.mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ProAgentEventHistoryScreen(
          agentTitle: agent['title']?.toString() ?? agent['agent_id']?.toString() ?? taskId,
          events: events,
        ),
      ));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load lifecycle history: $error')),
      );
    }
  }
}

class ProAgentEventHistoryScreen extends StatelessWidget {
  const ProAgentEventHistoryScreen({
    super.key,
    required this.agentTitle,
    required this.events,
  });

  final String agentTitle;
  final List<KernelEventRecord> events;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: ProTheme.bgDark,
    appBar: ProAppBar(title: 'Activity · $agentTitle'),
    body: events.isEmpty
        ? const Center(child: Text('No persisted lifecycle events found.', style: TextStyle(color: ProTheme.textSecondary)))
        : ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: events.length,
            separatorBuilder: (_, __) => const Divider(color: Colors.white12),
            itemBuilder: (context, index) {
              final event = events[index];
              final failed = event.status == 'failed' || event.status == 'error';
              final completed = event.status == 'completed';
              return ListTile(
                leading: Icon(
                  failed ? Icons.error_outline : completed ? Icons.check_circle_outline : Icons.timeline,
                  color: failed ? ProTheme.dangerRed : completed ? ProTheme.neonGreen : ProTheme.textSecondary,
                ),
                title: Text(event.type.replaceAll('_', ' '), style: const TextStyle(color: ProTheme.textPrimary)),
                subtitle: Text(
                  '${event.status} • ${event.createdAt.toLocal()}',
                  style: const TextStyle(color: ProTheme.textSecondary, fontSize: 11),
                ),
              );
            },
          ),
  );
}

Widget _header(String title, String status) => Container(
  padding: const EdgeInsets.all(18),
  decoration: BoxDecoration(
    gradient: ProTheme.cardGradient,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: ProTheme.neonGreen.withOpacity(.2)),
  ),
  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: const TextStyle(color: ProTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    Text(status, style: const TextStyle(color: ProTheme.neonGreen)),
  ]),
);

Widget _section(String title, List<Widget> children) => Container(
  margin: const EdgeInsets.only(top: 14),
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(gradient: ProTheme.cardGradient, borderRadius: BorderRadius.circular(16)),
  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: const TextStyle(color: ProTheme.neonGreen, fontWeight: FontWeight.bold)),
    const Divider(color: Colors.white12),
    ...children,
  ]),
);

Widget _row(String label, dynamic value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 5),
  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    SizedBox(width: 112, child: Text(label, style: const TextStyle(color: ProTheme.textSecondary, fontSize: 12))),
    Expanded(child: SelectableText(value?.toString() ?? '—', style: const TextStyle(color: ProTheme.textPrimary, fontSize: 12))),
  ]),
);
