import 'package:flutter/material.dart';

import '../services/pro_control_center.dart';
import '../theme/pro_theme.dart';
import 'pro_dashboard.dart';
import 'pro_task_manager.dart';
import 'pro_agent_fleet.dart';
import 'pro_battle_card.dart';
import 'pro_integrations.dart';
import 'pro_advanced_config.dart';

/// A single navigation shell for the six AgentsOS control surfaces.
/// IndexedStack preserves each screen's filters and scroll position while
/// switching tabs; the chat route remains the app's default entry point.
class ProAgentsOsHub extends StatefulWidget {
  const ProAgentsOsHub({super.key});

  @override
  State<ProAgentsOsHub> createState() => _ProAgentsOsHubState();
}

class _ProAgentsOsHubState extends State<ProAgentsOsHub> {
  int _selectedIndex = 0;
  final Set<int> _visited = {0};
  late final Future<void> _initialization;

  static const List<Widget> _pages = [
    ProDashboard(),
    ProTaskManager(),
    ProAgentFleet(),
    ProBattleCard(),
    ProIntegrations(),
    ProAdvancedConfig(),
  ];

  static const List<BottomNavigationBarItem> _items = [
    BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
    BottomNavigationBarItem(icon: Icon(Icons.task_alt), label: 'Tasks'),
    BottomNavigationBarItem(icon: Icon(Icons.smart_toy_outlined), label: 'Agents'),
    BottomNavigationBarItem(icon: Icon(Icons.insights_outlined), label: 'Battle'),
    BottomNavigationBarItem(icon: Icon(Icons.hub_outlined), label: 'Integrations'),
    BottomNavigationBarItem(icon: Icon(Icons.tune), label: 'Config'),
  ];

  @override
  void initState() {
    super.initState();
    _initialization = ProControlCenter.instance.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        return Scaffold(
          backgroundColor: ProTheme.bgDark,
          body: IndexedStack(
            index: _selectedIndex,
            children: List<Widget>.generate(_pages.length, (index) =>
              _visited.contains(index) ? _pages[index] : const SizedBox.shrink(),
            ),
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _selectedIndex,
            items: _items,
            type: BottomNavigationBarType.fixed,
            backgroundColor: ProTheme.bgCard,
            selectedItemColor: ProTheme.neonGreen,
            unselectedItemColor: ProTheme.textSecondary,
            onTap: (index) => setState(() {
              _visited.add(index);
              _selectedIndex = index;
            }),
          ),
          floatingActionButton: snapshot.hasError
              ? FloatingActionButton.small(
                  onPressed: () => ProControlCenter.instance.refresh(),
                  backgroundColor: ProTheme.dangerRed,
                  child: const Icon(Icons.refresh),
                )
              : null,
        );
      },
    );
  }
}
