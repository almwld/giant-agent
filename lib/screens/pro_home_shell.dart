import 'package:flutter/material.dart';

import '../services/pro_control_center.dart';
import '../theme/pro_theme.dart';
import 'chat_screen.dart';
import 'pro_dashboard.dart';
import 'pro_task_manager.dart';
import 'pro_agent_fleet.dart';
import 'pro_battle_card.dart';
import 'pro_integrations.dart';
import 'pro_advanced_config.dart';

/// Main application shell: chat is the landing screen and every control
/// surface is reachable directly from the persistent bottom navigation.
class ProHomeShell extends StatefulWidget {
  const ProHomeShell({super.key});

  @override
  State<ProHomeShell> createState() => _ProHomeShellState();
}

class _ProHomeShellState extends State<ProHomeShell> {
  int _selectedIndex = 0;
  final Set<int> _visited = {0};
  late final Future<void> _initialization;

  static const _destinations = <_HomeDestination>[
    _HomeDestination('الدردشة', Icons.chat_bubble_outline_rounded),
    _HomeDestination('الرئيسية', Icons.dashboard_outlined),
    _HomeDestination('المهام', Icons.task_alt_rounded),
    _HomeDestination('الوكلاء', Icons.smart_toy_outlined),
    _HomeDestination('المقارنة', Icons.insights_outlined),
    _HomeDestination('التكاملات', Icons.hub_outlined),
    _HomeDestination('الإعدادات', Icons.tune_rounded),
  ];

  static const List<Widget> _pages = <Widget>[
    ChatScreen(),
    ProDashboard(),
    ProTaskManager(),
    ProAgentFleet(),
    ProBattleCard(),
    ProIntegrations(),
    ProAdvancedConfig(),
  ];

  @override
  void initState() {
    super.initState();
    _initialization = ProControlCenter.instance.initialize();
  }

  void _select(int index) {
    if (index == _selectedIndex) return;
    setState(() {
      _visited.add(index);
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ProTheme.bgDark,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _selectedIndex,
          children: List<Widget>.generate(
            _pages.length,
            (index) => _visited.contains(index)
                ? _pages[index]
                : const SizedBox.shrink(),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 68,
          decoration: BoxDecoration(
            color: ProTheme.bgCard,
            border: Border(
              top: BorderSide(color: ProTheme.textSecondary.withValues(alpha: .18)),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: List<Widget>.generate(_destinations.length, (index) {
                final destination = _destinations[index];
                final selected = index == _selectedIndex;
                return Semantics(
                  button: true,
                  selected: selected,
                  label: destination.label,
                  child: InkWell(
                    onTap: () => _select(index),
                    borderRadius: BorderRadius.circular(14),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 76,
                      height: 58,
                      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                      decoration: BoxDecoration(
                        color: selected
                            ? ProTheme.neonGreen.withValues(alpha: .12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            destination.icon,
                            size: 21,
                            color: selected
                                ? ProTheme.neonGreen
                                : ProTheme.textSecondary,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            destination.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                              color: selected
                                  ? ProTheme.neonGreen
                                  : ProTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeDestination {
  const _HomeDestination(this.label, this.icon);
  final String label;
  final IconData icon;
}
