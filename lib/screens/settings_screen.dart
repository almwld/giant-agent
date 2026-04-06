import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _darkMode = true;
  int _messageCount = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadStats();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _darkMode = prefs.getBool('darkMode') ?? true;
    });
  }

  Future<void> _loadStats() async {
    final messages = await DatabaseService.getMessages();
    setState(() {
      _messageCount = messages.length;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkMode', _darkMode);
  }

  Future<void> _clearChat() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مسح المحادثة'),
        content: const Text('هل أنت متأكد من حذف جميع الرسائل؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(
            onPressed: () async {
              await DatabaseService.clearMessages();
              setState(() => _messageCount = 0);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم مسح المحادثة')),
              );
            },
            child: const Text('مسح', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات'),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          _buildSection('📊 الإحصائيات', [
            _buildInfoRow('عدد الرسائل', '$_messageCount'),
            _buildInfoRow('آخر تحديث', DateTime.now().toString().substring(0, 16)),
          ]),
          _buildSection('⚙️ التفضيلات', [
            SwitchListTile(
              title: const Text('الوضع الليلي'),
              value: _darkMode,
              onChanged: (value) {
                setState(() => _darkMode = value);
                _saveSettings();
              },
            ),
          ]),
          _buildSection('💾 إدارة البيانات', [
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('مسح المحادثة'),
              onTap: _clearChat,
            ),
          ]),
          _buildSection('📚 عن التطبيق', [
            const ListTile(
              title: Text('Giant Agent'),
              subtitle: Text('الوكيل العملاق للذكاء الاصطناعي'),
            ),
            const ListTile(
              title: Text('الإصدار'),
              subtitle: Text('1.0.0'),
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
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 100, child: Text(label, style: TextStyle(color: Colors.grey.shade400))),
          Text(value),
        ],
      ),
    );
  }
}
