import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../services/database_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _darkMode = false;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات'), centerTitle: true),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('الوضع المظلم'),
            value: _darkMode,
            onChanged: (value) => setState(() => _darkMode = value),
          ),
          ListTile(
            leading: const Icon(Icons.share),
            title: const Text('تصدير المحادثة'),
            onTap: () async {
              final content = await DatabaseService.exportToText();
              await Share.share(content);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep, color: Colors.red),
            title: const Text('مسح المحادثة', style: TextStyle(color: Colors.red)),
            onTap: () async {
              await DatabaseService.clearMessages();
              Navigator.pop(context);
            },
          ),
          const AboutListTile(
            applicationName: 'Giant Agent X',
            applicationVersion: '3.0.0',
            applicationIcon: Icon(Icons.bolt),
          ),
        ],
      ),
    );
  }
}
