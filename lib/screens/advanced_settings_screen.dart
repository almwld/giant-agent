import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/theme_service.dart';

class AdvancedSettingsScreen extends StatefulWidget {
  const AdvancedSettingsScreen({super.key});
  @override
  State<AdvancedSettingsScreen> createState() => _AdvancedSettingsScreenState();
}

class _AdvancedSettingsScreenState extends State<AdvancedSettingsScreen> {
  bool _notifications = true, _autoSave = true, _soundEffects = true, _vibration = true;
  double _fontSize = 14;
  String _language = 'ar';
  Color _accentColor = const Color(0xFF0A8F83);

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final accent = await ThemeService.getAccentColor();
    if (!mounted) return;
    setState(() {
      _notifications = prefs.getBool('notifications') ?? true;
      _autoSave = prefs.getBool('auto_save') ?? true;
      _soundEffects = prefs.getBool('sound_effects') ?? true;
      _vibration = prefs.getBool('vibration') ?? true;
      _fontSize = prefs.getDouble('font_size') ?? 14;
      _language = prefs.getString('language') ?? 'ar';
      _accentColor = accent;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications', _notifications);
    await prefs.setBool('auto_save', _autoSave);
    await prefs.setBool('sound_effects', _soundEffects);
    await prefs.setBool('vibration', _vibration);
    await prefs.setDouble('font_size', _fontSize);
    await prefs.setString('language', _language);
    await ThemeService.setAccentColor(_accentColor);
    if (!_notifications) await NotificationService().cancelAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Advanced Settings'), centerTitle: true),
      body: ListView(children: [
        _section('Theme', [
          SizedBox(
            height: 64,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: ThemeService.getAvailableColors().map((color) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: InkWell(
                  onTap: () => setState(() => _accentColor = color),
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: color,
                    child: _accentColor.value == color.value
                        ? const Icon(Icons.check, color: Colors.white)
                        : null,
                  ),
                ),
              )).toList(),
            ),
          ),
        ]),
        _section('Appearance', [
          SwitchListTile(
            title: const Text('Dark Mode'),
            value: Theme.of(context).brightness == Brightness.dark,
            onChanged: (_) => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Use the app theme control to change appearance.')),
            ),
          ),
          ListTile(
            title: const Text('Font Size'),
            subtitle: Slider(
              value: _fontSize.clamp(10.0, 24.0),
              min: 10, max: 24, divisions: 14,
              label: _fontSize.toStringAsFixed(0),
              onChanged: (value) => setState(() => _fontSize = value),
            ),
          ),
          ListTile(
            title: const Text('Language'),
            trailing: DropdownButton<String>(
              value: _language,
              items: const [
                DropdownMenuItem(value: 'ar', child: Text('العربية')),
                DropdownMenuItem(value: 'en', child: Text('English')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _language = value);
              },
            ),
          ),
        ]),
        _section('Notifications', [
          SwitchListTile(
            title: const Text('Enable Notifications'),
            value: _notifications,
            onChanged: (value) => setState(() => _notifications = value),
          ),
          SwitchListTile(
            title: const Text('Sound Effects'),
            value: _soundEffects,
            onChanged: (value) => setState(() => _soundEffects = value),
          ),
          SwitchListTile(
            title: const Text('Vibration'),
            value: _vibration,
            onChanged: (value) => setState(() => _vibration = value),
          ),
        ]),
        _section('Data', [
          SwitchListTile(
            title: const Text('Auto Save Conversations'),
            value: _autoSave,
            onChanged: (value) => setState(() => _autoSave = value),
          ),
          ListTile(
            leading: const Icon(Icons.backup),
            title: const Text('Backup Data'),
            onTap: () => _showUnavailable('Backup is not available yet.'),
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Restore Data'),
            onTap: () => _showUnavailable('Restore is not available yet.'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep, color: Colors.red),
            title: const Text('Clear All Data', style: TextStyle(color: Colors.red)),
            onTap: _confirmClearData,
          ),
        ]),
        _section('About', const [
          ListTile(leading: Icon(Icons.info), title: Text('Version'), subtitle: Text('6.0.0')),
          ListTile(leading: Icon(Icons.code), title: Text('Developer'), subtitle: Text('Giant AI Labs')),
        ]),
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.red),
          title: const Text('Sign Out', style: TextStyle(color: Colors.red)),
          onTap: _confirmSignOut,
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: _saveSettings,
            icon: const Icon(Icons.save),
            label: const Text('Save All Settings'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0A8F83),
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _section(String title, List<Widget> children) => Container(
    margin: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).cardColor,
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

  void _showUnavailable(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmClearData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear All Data'),
        content: const Text('This action cannot be undone. Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed == true && mounted) _showUnavailable('Data clearing is not connected yet.');
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Sign Out')),
        ],
      ),
    );
    if (confirmed == true) {
      await AuthService().logout();
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    }
  }
}
