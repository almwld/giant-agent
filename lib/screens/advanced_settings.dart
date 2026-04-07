import 'package:flutter/material.dart';
import '../services/theme_service.dart';
import '../services/notification_service.dart';
import '../services/backup_service.dart';

class AdvancedSettings extends StatefulWidget {
  const AdvancedSettings({super.key});

  @override
  State<AdvancedSettings> createState() => _AdvancedSettingsState();
}

class _AdvancedSettingsState extends State<AdvancedSettings> {
  ThemeMode _themeMode = ThemeMode.system;
  Color _accentColor = const Color(0xFF6C63FF);
  bool _notifications = true;
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }
  
  Future<void> _loadSettings() async {
    _themeMode = await ThemeService.getThemeMode();
    _accentColor = await ThemeService.getAccentColor();
    setState(() {});
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات متقدمة'), centerTitle: true),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('الإشعارات اليومية'),
            value: _notifications,
            onChanged: (value) => setState(() => _notifications = value),
          ),
          ListTile(
            title: const Text('الوضع'),
            trailing: DropdownButton<ThemeMode>(
              value: _themeMode,
              items: const [
                DropdownMenuItem(value: ThemeMode.light, child: Text('فاتح')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('مظلم')),
                DropdownMenuItem(value: ThemeMode.system, child: Text('النظام')),
              ],
              onChanged: (value) async {
                if (value != null) {
                  await ThemeService.setThemeMode(value);
                  setState(() => _themeMode = value);
                }
              },
            ),
          ),
          ListTile(
            title: const Text('اللون الرئيسي'),
            trailing: Wrap(
              spacing: 8,
              children: ThemeService.getAvailableColors().map((color) => GestureDetector(
                onTap: () async {
                  await ThemeService.setAccentColor(color);
                  setState(() => _accentColor = color);
                },
                child: Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle,
                    border: _accentColor == color ? Border.all(color: Colors.white, width: 2) : null),
                ),
              )).toList(),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.backup),
            title: const Text('نسخ احتياطي'),
            onTap: () => BackupService.backup(),
          ),
        ],
      ),
    );
  }
}
