import 'package:flutter/material.dart';
import '../services/model_service.dart';

class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key});

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  final ModelService _modelService = ModelService();

  @override
  Widget build(BuildContext context) {
    final model = _modelService.getActiveModel();
    final isLoaded = model['id'] != 'no_model' && _modelService.hasActiveModel();

    return Scaffold(
      appBar: AppBar(
        title: const Text('حالة أداء المحرك'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _modelService.refreshModels();
          if (mounted) setState(() {});
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildCard(
              title: 'النموذج النشط',
              value: model['name']?.toString() ?? 'لا يوجد نموذج',
              icon: Icons.memory,
              color: Colors.blue,
            ),
            _buildCard(
              title: 'حالة التحميل',
              value: isLoaded ? 'تم اختيار النموذج' : 'لا يوجد نموذج محدد',
              icon: Icons.check_circle_outline,
              color: isLoaded ? Colors.green : Colors.orange,
            ),
            _buildCard(
              title: 'حالة المحرك',
              value: _modelService.isBusy ? 'مشغول بالتنفيذ' : 'متاح',
              icon: Icons.speed,
              color: _modelService.isBusy ? Colors.orange : Colors.green,
            ),
            _buildCard(
              title: 'حجم النموذج',
              value: model['size']?.toString() ?? 'غير معروف',
              icon: Icons.storage,
              color: Colors.purple,
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
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, size: 30, color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 14, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
