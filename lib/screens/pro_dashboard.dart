import 'package:flutter/material.dart';
import '../services/pro_control_center.dart';
import '../domain/kernel/agent_observability.dart';
import '../theme/pro_theme.dart';
import '../widgets/pro_app_bar.dart';

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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _control,
      builder: (context, _) => Scaffold(
      backgroundColor: ProTheme.bgDark,
      appBar: const ProAppBar(title: 'Operational Control Center', breadcrumb: 'AgentOS / Dashboard'),
      body: Container(
        decoration: const BoxDecoration(gradient: ProTheme.bgGradient),
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<void>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              if (snapshot.hasError) return Center(child: Text(snapshot.error.toString(), style: const TextStyle(color: ProTheme.dangerRed)));
              final AgentObservabilitySummary? metrics = _control.metrics;
              if (metrics == null) return const Center(child: Text('No runtime metrics available', style: TextStyle(color: ProTheme.textSecondary)));
              final taskCount = _control.tasks.length;
              final agentCount = _control.agents.length;
              final integrationCount = _control.integrations.length;
              return ListView(
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
                  _panel('Lifecycle event distribution', metrics.eventTypes.entries.map((entry) => _line(entry.key, entry.value.toString())).toList()),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

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
