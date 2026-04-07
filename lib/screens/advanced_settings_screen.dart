import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/theme_service.dart';
import '../services/notification_service.dart';

class AdvancedSettingsScreen extends StatefulWidget {
  const AdvancedSettingsScreen({super.key});

  @override
  State<AdvancedSettingsScreen> createState() => _AdvancedSettingsScreenState();
}

class _AdvancedSettingsScreenState extends State<AdvancedSettingsScreen> {
  bool _notifications = true;
  bool _autoSave = true;
  bool _soundEffects = true;
  bool _vibration = true;
  double _fontSize = 14.0;
  String _language = 'ar';
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }
  
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notifications = prefs.getBool('notifications') ?? true;
      _autoSave = prefs.getBool('auto_save') ?? true;
      _soundEffects = prefs.getBool('sound_effects') ?? true;
      _vibration = prefs.getBool('vibration') ?? true;
      _fontSize = prefs.getDouble('font_size') ?? 14.0;
      _language = prefs.getString('language') ?? 'ar';
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
    
    if (!_notifications) {
      await NotificationService().cancelAll();
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved')),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Advanced Settings'),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          // Theme Section
          _buildSection('Theme', [
            _buildThemeSelector(),
          ]),
          
          // Appearance Section
          _buildSection('Appearance', [
            SwitchListTile(
              title: const Text('Dark Mode'),
              value: Theme.of(context).brightness == Brightness.dark,
              onChanged: (value) {
                // Toggle theme
              },
            ),
            ListTile(
              title: const Text('Font Size'),
              subtitle: Slider(
                value: _fontSize,
                min: 10,
                max: 24,
                divisions: 14,
                label: '${_fontSize.toStringAsFixed(0)}',
                onChanged: (value) {
                  setState(() => _fontSize = value);
                },
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
                  setState(() => _language = value!);
                },
              ),
            ),
          ]),
          
          // Notifications Section
          _buildSection('Notifications', [
            SwitchListTile(
              title: const Text('Enable Notifications'),
              value: _notifications,
              onChanged: (value) {
                setState(() => _notifications = value);
              },
            ),
            SwitchListTile(
              title: const Text('Sound Effects'),
              value: _soundEffects,
              onChanged: (value) {
                setState(() => _soundEffects = value);
              },
            ),
            SwitchListTile(
              title: const Text('Vibration'),
              value: _vibration,
              onChanged: (value) {
                setState(() => _vibration = value);
              },
            ),
          ]),
          
          // Data Section
          _buildSection('Data', [
            SwitchListTile(
              title: const Text('Auto Save Conversations'),
              value: _autoSave,
              onChanged: (value) {
                setState(() => _autoSave = value);
              },
            ),
            ListTile(
              leading: const Icon(Icons.backup),
              title: const Text('Backup Data'),
              onTap: () {
                // Backup logic
              },
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('Restore Data'),
              onTap: () {
                // Restore logic
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep, color: Colors.red),
              title: const Text('Clear All Data', style: TextStyle(color: Colors.red)),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Clear All Data'),
                    content: const Text('This action cannot be undone. Are you sure?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () {
                          // Clear data logic
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Data cleared')),
                          );
                        },
                        child: const Text('Clear', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ]),
          
          // About Section
          _buildSection('About', [
            const ListTile(
              leading: Icon(Icons.info),
              title: Text('Version'),
              subtitle: Text('4.0.0'),
            ),
            const ListTile(
              leading: Icon(Icons.code),
              title: Text('Developer'),
              subtitle: Text('Giant AI Labs'),
            ),
          ]),
          
          const SizedBox(height: 20),
          
          // Save Button
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: _saveSettings,
              icon: const Icon(Icons.save),
              label: const Text('Save All Settings'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10A37F),
                minimumSize: const Size(double.infinity, 48),
              ),
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
        color: Theme.of(context).cardColor,
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
  
  Widget _buildThemeSelector() {
    return SizedBox(
      height: 80,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: ThemeService.themes.length,
        itemBuilder: (context, index) {
          final theme = ThemeService.themes[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                IconButton(
                  icon: Icon(theme['icon']),
                  onPressed: () {
                    // Change theme
                  },
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF10A37F).withOpacity(0.1),
                  ),
                ),
                Text(theme['name']),
              ],
            ),
          );
        },
      ),
    );
  }
}

  // Logout button
  ListTile(
    leading: const Icon(Icons.logout, color: Colors.red),
    title: const Text('Sign Out', style: TextStyle(color: Colors.red)),
    onTap: () {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sign Out'),
          content: const Text('Are you sure you want to sign out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                await AuthService().logout();
                if (mounted) {
                  Navigator.pushReplacementNamed(context, '/login');
                }
              },
              child: const Text('Sign Out', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
    },
  ),
