import 'package:flutter/material.dart';
import '../agent/task_manager.dart';
import '../theme/pro_theme.dart';
import '../widgets/pro_app_bar.dart';

class ProTaskManager extends StatefulWidget {
  const ProTaskManager({super.key});
  @override
  State<ProTaskManager> createState() => _ProTaskManagerState();
}

class _ProTaskManagerState extends State<ProTaskManager> {
  final _manager = TaskManager();
  late Future<void> _loading;
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    _loading = _manager.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ProTheme.bgDark,
      appBar: const ProAppBar(title: 'Task Manager'),
      body: Container(
        decoration: const BoxDecoration(gradient: ProTheme.bgGradient),
        child: FutureBuilder<void>(
          future: _loading,
          builder: (context, state) {
            if (state.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.hasError) return Center(child: Text(state.error.toString()));
            final allTasks = _manager.getTasks();
            final tasks = allTasks.where((task) {
              final status = task['status']?.toString() ?? '';
              return _filter == 'All' ||
                  (_filter == 'In Progress' && status == 'running') ||
                  (_filter == 'Blocked' && status == 'paused') ||
                  (_filter == 'Completed' && status == 'completed');
            }).toList().reversed.toList();

            return Column(children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(12),
                child: Row(children: ['All', 'In Progress', 'Blocked', 'Completed'].map((filter) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(filter),
                      selected: _filter == filter,
                      onSelected: (_) => setState(() => _filter = filter),
                    ),
                  );
                }).toList()),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    await _manager.initialize();
                    if (mounted) setState(() {});
                  },
                  child: tasks.isEmpty
                      ? const ListView(children: [
                          SizedBox(height: 180),
                          Center(child: Text('No persisted tasks yet', style: TextStyle(color: ProTheme.textSecondary))),
                        ])
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: tasks.length,
                          itemBuilder: (context, index) {
                            final task = tasks[index];
                            final status = task['status']?.toString() ?? 'unknown';
                            return Card(
                              color: ProTheme.bgCard,
                              child: ListTile(
                                title: Text(task['description']?.toString() ?? 'Task', style: const TextStyle(color: ProTheme.textPrimary)),
                                subtitle: Text('$status • ${task['updated_at'] ?? task['created_at'] ?? ''}', style: const TextStyle(color: ProTheme.textSecondary, fontSize: 11)),
                                trailing: Icon(
                                  status == 'failed' ? Icons.error_outline : status == 'completed' ? Icons.check_circle : Icons.pending,
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
    );
  }
}
