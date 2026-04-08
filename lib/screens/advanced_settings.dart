import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../services/model_service.dart';

class AdvancedSettings extends StatefulWidget {
  const AdvancedSettings({super.key});

  @override
  State<AdvancedSettings> createState() => _AdvancedSettingsState();
}

class _AdvancedSettingsState extends State<AdvancedSettings> {
  final ModelService _modelService = ModelService();
  bool _darkMode = false;
  double _fontSize = 14.0;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات'),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          _buildSection('النماذج', [
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('تحديث النماذج'),
              subtitle: const Text('إعادة مسح مجلدات الهاتف'),
              onTap: () async {
                await _modelService.refreshModels();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم تحديث النماذج')),
                );
              },
            ),
          ]),
          _buildSection('المظهر', [
            SwitchListTile(
              title: const Text('الوضع المظلم'),
              value: _darkMode,
              onChanged: (value) => setState(() => _darkMode = value),
            ),
            ListTile(
              title: const Text('حجم الخط'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: () => setState(() => _fontSize = (_fontSize - 1).clamp(10, 24)),
                  ),
                  Text('${_fontSize.toStringAsFixed(0)}'),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => setState(() => _fontSize = (_fontSize + 1).clamp(10, 24)),
                  ),
                ],
              ),
            ),
          ]),
          _buildSection('معلومات', [
            ListTile(
              leading: const Icon(Icons.info),
              title: const Text('عن التطبيق'),
              subtitle: const Text('Giant Agent X - الإصدار 6.0'),
              onTap: () {
                showAboutDialog(
                  context: context,
                  applicationName: 'Giant Agent X',
                  applicationVersion: '6.0.0',
                  applicationIcon: const Icon(Icons.bolt, size: 40),
                  children: const [
                    Text('الوكيل العملاق للذكاء الاصطناعي'),
                    SizedBox(height: 8),
                    Text('• دعم نماذج TFLite'),
                    Text('• رفع ملفات وصور'),
                    Text('• محادثة ذكية'),
                  ],
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('مشاركة التطبيق'),
              onTap: () {
                Share.share('جرب تطبيق Giant Agent X - أقوى وكيل ذكاء اصطناعي!');
              },
            ),
          ]),
        ],
      ),
    );
  }
  
  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}
