import 'package:flutter/material.dart';
import '../services/model_service.dart';

class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key});

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  final ModelService _modelService = ModelService();
  Map<String, dynamic> _stats = {};
  
  @override
  void initState() {
    super.initState();
    _loadStats();
  }
  
  void _loadStats() {
    setState(() {
      _stats = _modelService.getPerformanceStats();
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إحصائيات الأداء'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _loadStats();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildCard(
              title: '⚡ سرعة الاستجابة',
              value: '${_stats['average_response_time_ms'] ?? 0} ms',
              icon: Icons.speed,
              color: Colors.blue,
            ),
            _buildCard(
              title: '📊 إجمالي الطلبات',
              value: '${_stats['total_requests'] ?? 0}',
              icon: Icons.request_page,
              color: Colors.green,
            ),
            _buildCard(
              title: '💾 نسبة التخزين المؤقت',
              value: '${_stats['cache_hit_rate'] ?? 0}%',
              icon: Icons.memory,
              color: Colors.orange,
            ),
            _buildCard(
              title: '📋 قائمة الانتظار',
              value: '${_stats['queue_size'] ?? 0}',
              icon: Icons.queue,
              color: Colors.purple,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                _loadStats();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم تحديث الإحصائيات')),
                );
              },
              icon: const Icon(Icons.refresh),
              label: const Text('تحديث'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 30, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
