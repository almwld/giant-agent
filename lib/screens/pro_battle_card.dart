import 'package:flutter/material.dart';
import '../services/pro_control_center.dart';
import '../theme/pro_theme.dart';
import '../widgets/pro_app_bar.dart';

class ProBattleCard extends StatefulWidget {
  const ProBattleCard({super.key});
  @override
  State<ProBattleCard> createState() => _ProBattleCardState();
}

class _ProBattleCardState extends State<ProBattleCard> {
  final _control = ProControlCenter.instance;
  late Future<void> _future;

  @override
  void initState() {
    super.initState();
    _future = _control.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _control,
      builder: (context, _) => Scaffold(
        backgroundColor: ProTheme.bgDark,
        appBar: const ProAppBar(title: 'Battle-card Hub'),
        body: Container(
          decoration: const BoxDecoration(gradient: ProTheme.bgGradient),
          child: FutureBuilder<void>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              final metrics = _control.metrics;
              return ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: ProTheme.cardGradient,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.orangeAccent.withOpacity(.3)),
                    ),
                    child: const Column(children: [
                      Icon(Icons.insights_outlined, color: Colors.orangeAccent, size: 42),
                      SizedBox(height: 14),
                      Text('Competitor intelligence is not configured', style: TextStyle(color: ProTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 17), textAlign: TextAlign.center),
                      SizedBox(height: 8),
                      Text('No competitor database, win/loss source, pricing feed or comparison provider is connected. This workspace will not invent competitor claims or demo metrics.', style: TextStyle(color: ProTheme.textSecondary, height: 1.5), textAlign: TextAlign.center),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(gradient: ProTheme.cardGradient, borderRadius: BorderRadius.circular(16)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Connected runtime context', style: TextStyle(color: ProTheme.neonGreen, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      _line('Recorded requests', metrics?.requestCount.toString() ?? '—'),
                      _line('Persisted tasks', _control.tasks.length.toString()),
                      _line('Subagents', _control.agents.length.toString()),
                      _line('MCP integrations', _control.integrations.length.toString()),
                      const SizedBox(height: 8),
                      const Text('These are live Giant Agent operational records, not competitor intelligence. Once a verified research source is added, battle cards can cite it alongside this execution context.', style: TextStyle(color: ProTheme.textSecondary, height: 1.4, fontSize: 12)),
                    ]),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(color: ProTheme.textSecondary))),
      Text(value, style: const TextStyle(color: ProTheme.textPrimary, fontWeight: FontWeight.w600)),
    ]),
  );
}
