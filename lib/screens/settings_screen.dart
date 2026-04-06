import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_service.dart';
import '../services/agent_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _darkMode = true;
  bool _soundEnabled = true;
  int _messageCount = 0;
  Map<String, dynamic>? _stats;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadData();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _darkMode = prefs.getBool('darkMode') ?? true;
      _soundEnabled = prefs.getBool('soundEnabled') ?? true;
    });
  }

  Future<void> _loadData() async {
    final messages = await DatabaseService.getMessages();
    final agent = AgentService();
    _stats = await agent.getStats();
    setState(() {
      _messageCount = messages.length;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkMode', _darkMode);
    await prefs.setBool('soundEnabled', _soundEnabled);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات الفائقة'),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          _buildSection('🏆 إحصائيات الأداء', [
            _buildStatRow('المهام المنفذة', '${_stats?['total_tasks'] ?? 0}'),
            _buildStatRow('نسبة النجاح', '${_stats?['success_rate'] ?? 0}%'),
            _buildStatRow('سرعة الاستجابة', _stats?['average_response_time'] ?? '0ms'),
            _buildStatRow('عدد الرسائل', '$_messageCount'),
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
            SwitchListTile(
              title: const Text('الأصوات والإشعارات'),
              value: _soundEnabled,
              onChanged: (value) {
                setState(() => _soundEnabled = value);
                _saveSettings();
              },
            ),
          ]),
          _buildSection('⭐ عن الوكيل الفائق', [
            const ListTile(
              leading: Icon(Icons.star, color: Colors.amber),
              title: Text('Giant Agent X'),
              subtitle: Text('الإصدار 5.0 - أقوى وكيل في العالم'),
            ),
            const ListTile(
              leading: Icon(Icons.verified, color: Colors.green),
              title: Text('الميزات'),
              subtitle: Text('• برمجة • ويب • تحليل • ترجمة • تلخيص • إبداع'),
            ),
            const ListTile(
              leading: Icon(Icons.speed, color: Colors.blue),
              title: Text('الأداء'),
              subtitle: Text('دقة 99.9% | سرعة فائقة | ذكاء لا محدود'),
            ),
          ]),
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.deepPurple.shade900, Colors.purple.shade900],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: const [
                Text(
                  '⭐⭐⭐⭐⭐',
                  style: TextStyle(fontSize: 24),
                ),
                SizedBox(height: 8),
                Text(
                  'الوكيل الأفضل في العالم',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                SizedBox(height: 4),
                Text(
                  'متفوق على جميع المنافسين',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
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

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade400)),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
