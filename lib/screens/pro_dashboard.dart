import 'package:flutter/material.dart';
import '../services/pro_control_center.dart';
import '../domain/kernel/agent_observability.dart';
import '../theme/pro_theme.dart';
import '../widgets/pro_app_bar.dart';
import 'pro_agentsos_detail_screens.dart';

class ProDashboard extends StatefulWidget {
  const ProDashboard({super.key});
  @override
  State<ProDashboard> createState() => _ProDashboardState();
}

class _ProDashboardState extends State<ProDashboard> {
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

  Future<void> _openTask(Map<String, dynamic> task) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ProTaskDetailScreen(task: Map<String, dynamic>.unmodifiable(task)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _control,
      builder: (context, _) => Scaffold(
        backgroundColor: ProTheme.bgDark,
        appBar: ProAppBar(title: 'Operational Control Center', breadcrumb: 'AgentOS / Dashboard'),
        body: Container(
          decoration: const BoxDecoration(gradient: ProTheme.bgGradient),
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: FutureBuilder<void>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const ListView(children: [SizedBox(height: 220), Center(child: CircularProgressIndicator())]);
                }
                if (snapshot.hasError) return ListView(children: [
                  const SizedBox(height: 180),
                  Center(child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('Runtime data unavailable: ${snapshot.error}', textAlign: TextAlign.center, style: const TextStyle(color: ProTheme.dangerRed)),
                      const SizedBox(height: 12),
                      FilledButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('Retry')),
                    ]),
                  )),
                ]);
                final AgentObservabilitySummary? metrics = _control.metrics;
                if (metrics == null) return ListView(children: const [
                  SizedBox(height: 180),
                  Center(child: Text('No runtime metrics available', style: TextStyle(color: ProTheme.textSecondary))),
                ]);
                final taskCount = _control.tasks.length;
                final agentCount = _control.agents.length;
                final integrationCount = _control.integrations.length;
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    _metricGrid(context, [
                      ('Requests', metrics.requestCount.toString(), Icons.bolt),
                      ('Active', metrics.activeRequests.toString(), Icons.sync),
                      ('Completed', metrics.completedRequests.toString(), Icons.check_circle_outline),
                      ('Failed', metrics.failedRequests.toString(), Icons.error_outline),
                      ('Tasks', taskCount.toString(), Icons.task_alt),
                      ('Agents', agentCount.toString(), Icons.smart_toy_outlined),
                      ('MCP servers', integrationCount.toString(), Icons.hub_outlined),
                      ('Events', metrics.eventCount.toString(), Icons.timeline),
                      ('Tool calls', metrics.toolCallCount.toString(), Icons.build_circle_outlined),
                    ]),
                    const SizedBox(height: 18),
                    _panel('Execution quality', [
                      _line('Tool success rate', '${(metrics.toolSuccessRate * 100).toStringAsFixed(1)}%'),
                      _line('Tool failures', metrics.toolFailureCount.toString()),
                      _line('Interrupted requests', metrics.interruptedRequests.toString()),
                      _line('Average tool latency', metrics.averageToolLatencyMs == null ? '—' : '${metrics.averageToolLatencyMs!.toStringAsFixed(0)} ms'),
                      _line('Last synchronized', _control.lastUpdated?.toLocal().toString() ?? '—'),
                    ]),
                    const SizedBox(height: 18),
                    _panel('Lifecycle event distribution', metrics.eventTypes.isEmpty
                        ? [const Text('No lifecycle events recorded yet.', style: TextStyle(color: ProTheme.textSecondary))]
                        : metrics.eventTypes.entries.map((entry) => _line(entry.key, entry.value.toString())).toList()),
                    const SizedBox(height: 18),
                    _sectionTitle('Recent activity', 'Latest persisted lifecycle events'),
                    if (_control.recentEvents.isEmpty)
                      _empty('No persisted events are available for this conversation.')
                    else
                      ..._control.recentEvents.take(12).map(_eventTile),
                    const SizedBox(height: 18),
                    _sectionTitle('Recent tasks', 'Open a task to inspect its saved lifecycle and recovery state'),
                    if (_control.tasks.isEmpty)
                      _empty('Tasks will appear here after they are created.')
                    else
                      ..._control.tasks.reversed.take(5).map((task) => Card(
                        color: ProTheme.bgCard,
                        child: ListTile(
                          onTap: () => _openTask(task),
                          leading: const Icon(Icons.task_alt, color: ProTheme.neonGreen),
                          title: Text(task['description']?.toString() ?? 'Task', maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: ProTheme.textPrimary)),
                          subtitle: Text('${task['status'] ?? 'unknown'} • ${task['id'] ?? ''}',
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: ProTheme.textSecondary, fontSize: 11)),
                          trailing: const Icon(Icons.chevron_right, color: ProTheme.textSecondary),
                        ),
                      )),
                    const SizedBox(height: 12),
                    Text('Metrics and activity are read from the shared AgentService observability journal and durable task/MCP projections. Event payloads and prompt contents are intentionally not displayed here.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: ProTheme.textSecondary)),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _eventTile(AgentObservabilityEvent event) => Card(
    color: ProTheme.bgCard,
    child: ListTile(
      dense: true,
      leading: Icon(_eventIcon(event.status), color: _eventColor(event.status)),
      title: Text(event.type.replaceAll('_', ' '), style: const TextStyle(color: ProTheme.textPrimary, fontWeight: FontWeight.w600)),
      subtitle: Text('${event.status} • ${event.createdAt.toLocal()}',
          style: const TextStyle(color: ProTheme.textSecondary, fontSize: 11)),
      trailing: event.taskId == null ? null : const Icon(Icons.link, color: ProTheme.textSecondary, size: 18),
    ),
  );

  IconData _eventIcon(String status) {
    if (status == 'failed' || status == 'error') return Icons.error_outline;
    if (status == 'completed') return Icons.check_circle_outline;
    if (status == 'running' || status == 'queued') return Icons.sync;
    return Icons.info_outline;
  }

  Color _eventColor(String status) {
    if (status == 'failed' || status == 'error') return ProTheme.dangerRed;
    if (status == 'completed') return ProTheme.neonGreen;
    return ProTheme.textSecondary;
  }

  Widget _sectionTitle(String title, String subtitle) => Padding(
    padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(color: ProTheme.neonGreen, fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 3),
      Text(subtitle, style: const TextStyle(color: ProTheme.textSecondary, fontSize: 12)),
    ]),
  );

  Widget _empty(String message) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: ProTheme.bgCard, borderRadius: BorderRadius.circular(14)),
    child: Text(message, textAlign: TextAlign.center, style: const TextStyle(color: ProTheme.textSecondary)),
  );

  Widget _metricGrid(BuildContext context, List<(String, String, IconData)> items) => GridView.count(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 3 : 2,
    childAspectRatio: 1.7,
    crossAxisSpacing: 10,
    mainAxisSpacing: 10,
    children: items.map((item) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(gradient: ProTheme.cardGradient, borderRadius: BorderRadius.circular(15), border: Border.all(color: ProTheme.neonGreen.withOpacity(.15))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(item.$3, color: ProTheme.neonGreen),
        const Spacer(),
        Text(item.$2, style: const TextStyle(color: ProTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
        Text(item.$1, style: const TextStyle(color: ProTheme.textSecondary, fontSize: 12)),
      ]),
    )).toList(),
  );

  Widget _panel(String title, List<Widget> children) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(gradient: ProTheme.cardGradient, borderRadius: BorderRadius.circular(16)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(color: ProTheme.neonGreen, fontWeight: FontWeight.bold)),
      const Divider(color: Colors.white12),
      ...children,
    ]),
  );

  Widget _line(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(color: ProTheme.textSecondary))),
      Text(value, style: const TextStyle(color: ProTheme.textPrimary, fontWeight: FontWeight.w600)),
    ]),
  );
}
