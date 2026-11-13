import 'package:flutter/material.dart';

import '../services/pro_control_center.dart';
import '../theme/pro_theme.dart';
import '../widgets/pro_app_bar.dart';

class ProTaskManager extends StatefulWidget {
  const ProTaskManager({super.key});
  @override
  State<ProTaskManager> createState() => _ProTaskManagerState();
}

class _ProTaskManagerState extends State<ProTaskManager> {
  final _control = ProControlCenter.instance;
  late Future<void> _loading;
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    _loading = _control.initialize();
  }

  Future<void> _resume(String taskId) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Resume task?'),
        content: const Text('The task may repeat external side effects. Review its saved checkpoint and external state before continuing. Resume only if it is safe.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Resume')),
        ],
      ),
    );
    if (approved != true) return;
    try {
      await _control.resumeTask(taskId);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _cancel() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel active task?'),
        content: const Text('The runtime will receive a cancellation request. A tool already performing an external action may need to finish its safe cancellation boundary.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep running')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Cancel task')),
        ],
      ),
    );
    if (approved != true) return;
    try {
      final accepted = await _control.cancelCurrentTask();
      if (mounted && !accepted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No active task accepted cancellation.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _control,
      builder: (context, _) => Scaffold(
        backgroundColor: ProTheme.bgDark,
        appBar: const ProAppBar(title: 'Task Manager'),
        body: Container(
          decoration: const BoxDecoration(gradient: ProTheme.bgGradient),
          child: FutureBuilder<void>(
            future: _loading,
            builder: (context, state) {
              if (state.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              if (state.hasError) return Center(child: Text(state.error.toString()));
              final tasks = _control.tasks.where((task) {
                final status = task['status']?.toString() ?? '';
                return _filter == 'All' ||
                    (_filter == 'In Progress' && status == 'running') ||
                    (_filter == 'Blocked' && status == 'paused') ||
                    (_filter == 'Completed' && status == 'completed') ||
                    (_filter == 'Failed' && status == 'failed');
              }).toList().reversed.toList();
              return Column(children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(12),
                  child: Row(children: ['All', 'In Progress', 'Blocked', 'Completed', 'Failed'].map((filter) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(label: Text(filter), selected: _filter == filter, onSelected: (_) => setState(() => _filter = filter)),
                  )).toList()),
                ),
                if (_control.isTaskExecuting)
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _cancel,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('Request cancellation of active task'),
                      ),
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async => _control.refresh(),
                    child: tasks.isEmpty
                      ? ListView(children: const [SizedBox(height: 180), Center(child: Text('No persisted tasks yet', style: TextStyle(color: ProTheme.textSecondary)))])
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: tasks.length,
                          itemBuilder: (context, index) {
                            final task = tasks[index];
                            final status = task['status']?.toString() ?? 'unknown';
                            final id = task['id']?.toString() ?? '';
                            final canResume = status == 'paused' || status == 'failed' || status == 'pending';
                            return Card(
                              color: ProTheme.bgCard,
                              child: ListTile(
                                title: Text(task['description']?.toString() ?? 'Task', style: const TextStyle(color: ProTheme.textPrimary)),
                                subtitle: Text('$status • ${task['updated_at'] ?? task['created_at'] ?? ''}', style: const TextStyle(color: ProTheme.textSecondary, fontSize: 11)),
                                trailing: canResume
                                  ? IconButton(
                                      tooltip: 'Review and resume',
                                      icon: const Icon(Icons.play_circle_outline, color: ProTheme.neonGreen),
                                      onPressed: () => _resume(id),
                                    )
                                  : Icon(
                                      status == 'failed' ? Icons.error_outline : status == 'completed' ? Icons.check_circle : status == 'running' ? Icons.sync : Icons.pending,
                                      color: status == 'failed' ? ProTheme.dangerRed : ProTheme.neonGreen,
                                    ),
                              ),
                            );
                          },
                        ),
                  ),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}
