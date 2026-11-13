import 'package:flutter/material.dart';
import '../services/pro_control_center.dart';
import '../theme/pro_theme.dart';
import '../widgets/pro_app_bar.dart';

class ProAgentFleet extends StatefulWidget {
  const ProAgentFleet({super.key});
  @override
  State<ProAgentFleet> createState() => _ProAgentFleetState();
}

class _ProAgentFleetState extends State<ProAgentFleet> {
  final _control = ProControlCenter.instance;
  late Future<void> _future;

  @override
  void initState() {
    super.initState();
    _future = _control.initialize();
  }

  Future<void> _refresh() async {
    setState(() => _future = _control.refresh());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ProTheme.bgDark,
      appBar: const ProAppBar(title: 'Agent Fleet Overview'),
      body: Container(
        decoration: const BoxDecoration(gradient: ProTheme.bgGradient),
        child: FutureBuilder<void>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError) return Center(child: Text(snapshot.error.toString()));
            final agents = _control.agents;
            if (agents.isEmpty) return const Center(child: Padding(
              padding: EdgeInsets.all(28),
              child: Text('No persisted subagent activity yet. Delegated agents appear here when work is recorded.', textAlign: TextAlign.center, style: TextStyle(color: ProTheme.textSecondary)),
            ));
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: agents.length,
                itemBuilder: (context, index) {
                  final agent = agents[index];
                  final id = agent['task_id']?.toString() ?? agent['id']?.toString() ?? '';
                  final status = agent['status']?.toString() ?? 'unknown';
                  return Card(
                    color: ProTheme.bgCard,
                    child: ListTile(
                      leading: const Icon(Icons.smart_toy, color: ProTheme.neonGreen),
                      title: Text(agent['title']?.toString() ?? agent['agent_id']?.toString() ?? 'Subagent', style: const TextStyle(color: ProTheme.textPrimary)),
                      subtitle: Text('$status • $id', style: const TextStyle(color: ProTheme.textSecondary, fontSize: 11)),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) async {
                          try {
                            if (value == 'cancel') await _control.cancelAgent(id);
                            if (value == 'dismiss') await _control.dismissAgent(id);
                            if (mounted) setState(() {});
                          } catch (error) {
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'cancel', child: Text('Cancel')),
                          PopupMenuItem(value: 'dismiss', child: Text('Dismiss')),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
