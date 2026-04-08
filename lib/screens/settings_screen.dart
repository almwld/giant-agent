import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF343541),
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF202123),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          _buildSection('App Settings', [
            _buildSettingTile(Icons.language, 'Language', 'English'),
            _buildSettingTile(Icons.dark_mode, 'Dark Mode', 'On'),
          ]),
          _buildSection('Model Settings', [
            _buildSettingTile(Icons.model_training, 'Context Size', '4096'),
            _buildSettingTile(Icons.memory, 'Use Memory Lock', 'Enabled'),
            _buildSettingTile(Icons.speed, 'Auto Offload', 'Disabled'),
          ]),
          _buildSection('Data', [
            _buildSettingTile(Icons.backup, 'Export Chats', 'Backup'),
            _buildSettingTile(Icons.share, 'Share App', ''),
          ]),
          _buildSection('About', [
            _buildSettingTile(Icons.info, 'Version', '7.0.0'),
            _buildSettingTile(Icons.code, 'Developer', 'Giant AI Labs'),
          ]),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF202123),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              title,
              style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSettingTile(IconData icon, String title, String subtitle) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: subtitle.isNotEmpty ? Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)) : null,
      trailing: const Icon(Icons.chevron_right, color: Colors.white70),
      onTap: () {},
    );
  }
}
