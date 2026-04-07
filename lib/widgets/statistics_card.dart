import 'package:flutter/material.dart';
import '../services/statistics_service.dart';
import '../core/theme.dart';

class StatisticsCard extends StatefulWidget {
  const StatisticsCard({super.key});

  @override
  State<StatisticsCard> createState() => _StatisticsCardState();
}

class _StatisticsCardState extends State<StatisticsCard> {
  final StatisticsService _stats = StatisticsService();
  Map<String, dynamic> _data = {};
  
  @override
  void initState() {
    super.initState();
    _loadStats();
  }
  
  Future<void> _loadStats() async {
    await _stats.init();
    final stats = await _stats.getStatistics();
    setState(() {
      _data = stats;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'إحصائيات سريعة',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  '📊',
                  '${_data['total_events'] ?? 0}',
                  'إجمالي الأحداث',
                ),
                _buildStatItem(
                  '📅',
                  '${_data['today_events'] ?? 0}',
                  'اليوم',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatItem(String icon, String value, String label) {
    return Column(
      children: [
        Text(icon, style: const TextStyle(fontSize: 24)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}
