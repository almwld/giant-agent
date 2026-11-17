import 'package:flutter/material.dart';
import 'pro_feature_directory.dart';

import '../domain/kernel/agent_kernel_store.dart';
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
  final _store = AgentKernelStore.shared;
  late Future<void> _future;
  List<Map<String, dynamic>> _evidence = const [];

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<void> _load() async {
    await _control.initialize();
    _evidence = await _store.getBattleCards();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
    if (mounted) setState(() {});
  }

  Future<void> _addEvidence([Map<String, dynamic>? existing]) async {
    final competitor = TextEditingController(text: existing?['competitor']?.toString() ?? '');
    final product = TextEditingController(text: existing?['product']?.toString() ?? '');
    final pricing = TextEditingController(text: existing?['pricing']?.toString() ?? '');
    final sourceUrl = TextEditingController(text: existing?['source_url']?.toString() ?? '');
    final sourceDate = TextEditingController(
      text: existing?['source_date']?.toString() ??
          DateTime.now().toIso8601String().substring(0, 10),
    );
    final excerpt = TextEditingController(text: existing?['evidence_excerpt']?.toString() ?? '');
    String confidence = existing?['confidence']?.toString() ?? 'medium';
    try {
      final values = await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(existing == null ? 'Add competitor evidence' : 'Edit competitor evidence'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: competitor, decoration: const InputDecoration(labelText: 'Competitor name')),
                TextField(controller: product, decoration: const InputDecoration(labelText: 'Product / offering (optional)')),
                TextField(controller: pricing, decoration: const InputDecoration(labelText: 'Pricing observation (optional)')),
                TextField(controller: sourceUrl, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Source URL (HTTPS)')),
                TextField(controller: sourceDate, decoration: const InputDecoration(labelText: 'Source date (YYYY-MM-DD)')),
                TextField(controller: excerpt, minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'Evidence excerpt (20–5000 characters)')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: confidence,
                  decoration: const InputDecoration(labelText: 'Confidence'),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Low')),
                    DropdownMenuItem(value: 'medium', child: Text('Medium')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => confidence = value);
                  },
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, {
                  'competitor': competitor.text.trim(),
                  'product': product.text.trim(),
                  'pricing': pricing.text.trim(),
                  'source_url': sourceUrl.text.trim(),
                  'source_date': sourceDate.text.trim(),
                  'evidence_excerpt': excerpt.text.trim(),
                  'confidence': confidence,
                }),
                child: Text(existing == null ? 'Save evidence' : 'Update evidence'),
              ),
            ],
          ),
        ),
      );
      if (values == null) return;
      final id = existing?['id']?.toString() ?? 'battle_${DateTime.now().microsecondsSinceEpoch}';
      await _store.saveBattleCard({'id': id, ...values});
      await _refresh();
      if (mounted) _message('Source evidence saved.');
    } catch (error) {
      if (mounted) _message(error.toString(), isError: true);
    } finally {
      competitor.dispose();
      product.dispose();
      pricing.dispose();
      sourceUrl.dispose();
      sourceDate.dispose();
      excerpt.dispose();
    }
  }

  Future<void> _deleteEvidence(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete evidence?'),
        content: const Text('This removes the saved evidence record from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _store.deleteBattleCard(id);
      await _refresh();
    } catch (error) {
      if (mounted) _message(error.toString(), isError: true);
    }
  }

  void _message(String value, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(value),
      backgroundColor: isError ? ProTheme.dangerRed : ProTheme.bgCard,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _control,
      builder: (context, _) => Scaffold(
        backgroundColor: ProTheme.bgDark,
        appBar: ProAppBar(
          title: 'Battle Cards',
          showAddButton: true,
          onAddPressed: _addEvidence,
          onToolsPressed: () => openProFeatureDirectory(context),
        ),
        body: Container(
          decoration: const BoxDecoration(gradient: ProTheme.bgGradient),
          child: FutureBuilder<void>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(snapshot.error.toString(), textAlign: TextAlign.center, style: const TextStyle(color: ProTheme.dangerRed)),
                    const SizedBox(height: 12),
                    FilledButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('Retry')),
                  ]),
                ));
              }
              final metrics = _control.metrics;
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    _panel('Competitor intelligence', [
                      const Text(
                        'Evidence workspace. Records are manually sourced and are not generated from operational telemetry.',
                        style: TextStyle(color: ProTheme.textSecondary, height: 1.45),
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        const Icon(Icons.verified_outlined, color: ProTheme.neonGreen),
                        const SizedBox(width: 8),
                        Text('${_evidence.length} saved evidence record(s)', style: const TextStyle(color: ProTheme.textPrimary, fontWeight: FontWeight.w600)),
                      ]),
                    ]),
                    const SizedBox(height: 14),
                    _panel('Connected runtime context', [
                      _line('Recorded requests', metrics?.requestCount.toString() ?? '—'),
                      _line('Persisted tasks', _control.tasks.length.toString()),
                      _line('Subagents', _control.agents.length.toString()),
                      _line('MCP integrations', _control.integrations.length.toString()),
                      const SizedBox(height: 8),
                      const Text('These are live Giant Agent operational records, not competitor metrics.', style: TextStyle(color: ProTheme.textSecondary, fontSize: 12)),
                    ]),
                    const SizedBox(height: 14),
                    Row(children: [
                      const Expanded(child: Text('Evidence library', style: TextStyle(color: ProTheme.neonGreen, fontSize: 16, fontWeight: FontWeight.bold))),
                      TextButton.icon(onPressed: _addEvidence, icon: const Icon(Icons.add), label: const Text('Add source')),
                    ]),
                    if (_evidence.isEmpty)
                      _panel('No evidence yet', [
                        const Text('Add a competitor, dated HTTPS source, evidence excerpt and confidence level. The app will not invent market claims, win rates or pricing.', style: TextStyle(color: ProTheme.textSecondary, height: 1.5)),
                      ])
                    else
                      ..._evidence.map(_evidenceCard),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _evidenceCard(Map<String, dynamic> item) => Card(
    color: ProTheme.bgCard,
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.business_outlined, color: ProTheme.neonGreen),
          const SizedBox(width: 8),
          Expanded(child: Text(item['competitor']?.toString() ?? 'Competitor', style: const TextStyle(color: ProTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16))),
          IconButton(
            tooltip: 'Edit evidence',
            onPressed: () => _addEvidence(item),
            icon: const Icon(Icons.edit_outlined, color: ProTheme.neonGreen),
          ),
          IconButton(
            tooltip: 'Delete evidence',
            onPressed: () => _deleteEvidence(item['id'].toString()),
            icon: const Icon(Icons.delete_outline, color: ProTheme.textSecondary),
          ),
        ]),
        if ((item['product'] ?? '').toString().isNotEmpty) _line('Product', item['product'].toString()),
        if ((item['pricing'] ?? '').toString().isNotEmpty) _line('Pricing', item['pricing'].toString()),
        _line('Source date', item['source_date'].toString()),
        _line('Confidence', item['confidence'].toString().toUpperCase()),
        const SizedBox(height: 8),
        SelectableText(item['evidence_excerpt'].toString(), style: const TextStyle(color: ProTheme.textPrimary, height: 1.4)),
        const SizedBox(height: 8),
        SelectableText(item['source_url'].toString(), style: const TextStyle(color: ProTheme.neonGreenDim, fontSize: 12)),
      ]),
    ),
  );

  Widget _panel(String title, List<Widget> children) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: ProTheme.bgCard,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFF2A2A2E)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(color: ProTheme.neonGreen, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      ...children,
    ]),
  );

  Widget _line(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Text(label, style: const TextStyle(color: ProTheme.textSecondary))),
      const SizedBox(width: 12),
      Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(color: ProTheme.textPrimary, fontWeight: FontWeight.w600))),
    ]),
  );
}
