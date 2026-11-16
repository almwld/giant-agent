import 'package:flutter/material.dart';

import '../theme/pro_theme.dart';
import '../widgets/pro_app_bar.dart';
import 'advanced_settings_screen.dart';
import 'agent_observability_screen.dart';
import 'agent_workflow_screen.dart';
import 'agent_workspace_screen.dart';
import 'benchmark_screen.dart';
import 'file_browser.dart';
import 'performance_screen.dart';
import 'stats_screen.dart';

/// Secondary directory for the supporting tools behind the six AgentsOS
/// control surfaces. Each destination opens the existing production screen.
class ProFeatureDirectoryScreen extends StatelessWidget {
  const ProFeatureDirectoryScreen({super.key});

  static const _groups = <_FeatureGroup>[
    _FeatureGroup('Execution & workspace', [
      _Feature('Agent workflow', 'Inspect the current run timeline and output.', Icons.account_tree_outlined, _FeatureRoute.workflow),
      _Feature('Workspace', 'Browse, edit and preview workspace files.', Icons.folder_open_outlined, _FeatureRoute.workspace),
      _Feature('Model library', 'Import and manage local GGUF models.', Icons.memory_outlined, _FeatureRoute.models),
    ]),
    _FeatureGroup('Monitoring & diagnostics', [
      _Feature('Live observability', 'Inspect persisted events, filters and runtime activity.', Icons.monitor_heart_outlined, _FeatureRoute.observability),
      _Feature('Engine performance', 'Check the active model and runtime readiness.', Icons.speed_outlined, _FeatureRoute.performance),
      _Feature('Usage statistics', 'Review application usage counters.', Icons.query_stats_outlined, _FeatureRoute.stats),
      _Feature('Model benchmark', 'Run a response-time benchmark against the loaded local model.', Icons.timer_outlined, _FeatureRoute.benchmark),
    ]),
    _FeatureGroup('Preferences', [
      _Feature('Advanced app settings', 'Manage language, notifications and display preferences.', Icons.settings_outlined, _FeatureRoute.settings),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ProTheme.bgDark,
      appBar: const ProAppBar(
        title: 'Tools & services',
        breadcrumb: 'AgentOS / Directory',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const Text(
            'All supporting AgentOS tools in one place',
            style: TextStyle(color: ProTheme.textSecondary, height: 1.45),
          ),
          const SizedBox(height: 16),
          for (final group in _groups) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 9, top: 8),
              child: Text(
                group.title,
                style: const TextStyle(
                  color: ProTheme.neonGreen,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final feature in group.features)
              Card(
                margin: const EdgeInsets.only(bottom: 9),
                child: ListTile(
                  leading: Icon(feature.icon, color: ProTheme.neonGreen),
                  title: Text(feature.title, style: const TextStyle(color: ProTheme.textPrimary, fontWeight: FontWeight.w600)),
                  subtitle: Text(feature.description, style: const TextStyle(color: ProTheme.textSecondary)),
                  trailing: const Icon(Icons.chevron_right, color: ProTheme.textSecondary),
                  onTap: () => _open(context, feature.route),
                ),
              ),
          ],
        ],
      ),
    );
  }

  void _open(BuildContext context, _FeatureRoute route) {
    final Widget page = switch (route) {
      _FeatureRoute.workflow => const AgentWorkflowScreen(),
      _FeatureRoute.workspace => const AgentWorkspaceScreen(steps: []),
      _FeatureRoute.models => const FileBrowser(),
      _FeatureRoute.observability => const AgentObservabilityScreen(conversationId: 'home'),
      _FeatureRoute.performance => const PerformanceScreen(),
      _FeatureRoute.stats => const StatsScreen(),
      _FeatureRoute.benchmark => const BenchmarkScreen(),
      _FeatureRoute.settings => const AdvancedSettingsScreen(),
    };
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

Future<void> openProFeatureDirectory(BuildContext context) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ProFeatureDirectoryScreen(),
      ),
    );

enum _FeatureRoute {
  workflow,
  workspace,
  models,
  observability,
  performance,
  stats,
  benchmark,
  settings,
}

class _Feature {
  const _Feature(this.title, this.description, this.icon, this.route);
  final String title;
  final String description;
  final IconData icon;
  final _FeatureRoute route;
}

class _FeatureGroup {
  const _FeatureGroup(this.title, this.features);
  final String title;
  final List<_Feature> features;
}
