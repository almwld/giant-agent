import 'package:flutter/material.dart';
import '../services/app_preferences.dart';
import 'mcp_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final prefs = AppPreferences.instance;
    return AnimatedBuilder(
      animation: prefs,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(prefs.locale.languageCode == 'ar' ? 'الإعدادات' : 'Settings')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          _heading(context, prefs.locale.languageCode == 'ar' ? 'المظهر' : 'Appearance'),
          Card(child: Column(children: [
            _themeOption(prefs, ThemeMode.system, prefs.locale.languageCode == 'ar' ? 'حسب النظام' : 'System'),
            _themeOption(prefs, ThemeMode.light, prefs.locale.languageCode == 'ar' ? 'فاتح' : 'Light'),
            _themeOption(prefs, ThemeMode.dark, prefs.locale.languageCode == 'ar' ? 'داكن' : 'Dark'),
          ])),
          const SizedBox(height: 18),
          _heading(context, prefs.locale.languageCode == 'ar' ? 'اللغة والاتجاه' : 'Language & direction'),
          Card(child: Column(children: [
            RadioListTile<String>(value: 'ar', groupValue: prefs.locale.languageCode,
              title: const Text('العربية — RTL'), onChanged: (_) => prefs.setLocale(const Locale('ar'))),
            RadioListTile<String>(value: 'en', groupValue: prefs.locale.languageCode,
              title: const Text('English — LTR'), onChanged: (_) => prefs.setLocale(const Locale('en'))),
          ])),
          const SizedBox(height: 18),
          _heading(context, prefs.locale.languageCode == 'ar' ? 'التشغيل' : 'Runtime'),
          Card(child: ListTile(
            leading: const Icon(Icons.hub_outlined),
            title: Text(prefs.locale.languageCode == 'ar' ? 'خوادم MCP' : 'MCP servers'),
            subtitle: Text(prefs.locale.languageCode == 'ar'
              ? 'إدارة الخوادم واكتشاف الأدوات والموارد الخارجية.'
              : 'Manage servers and discover external tools and resources.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const McpSettingsScreen()),
            ),
          )),
          Card(child: ListTile(leading: const Icon(Icons.memory_outlined),
            title: Text(prefs.locale.languageCode == 'ar' ? 'النموذج المحلي GGUF' : 'Local GGUF model'),
            subtitle: Text(prefs.locale.languageCode == 'ar'
              ? 'حالة النموذج والمهمة تُحفظ محلياً. استمرار الاستدلال أثناء إغلاق الواجهة يتطلب نقل المحرك إلى خدمة Android أمامية.'
              : 'Model and task state are stored locally. Continuous inference with the UI closed requires moving the runtime into an Android foreground service.'))),
          Card(child: ListTile(leading: const Icon(Icons.storage_outlined),
            title: Text(prefs.locale.languageCode == 'ar' ? 'التخزين المحلي' : 'Local storage'),
            subtitle: Text(prefs.locale.languageCode == 'ar' ? 'المحادثات محفوظة على هذا الجهاز.' : 'Conversations are stored on this device.'))),
        ]),
      ),
    );
  }

  Widget _themeOption(AppPreferences prefs, ThemeMode mode, String label) =>
    RadioListTile<ThemeMode>(value: mode, groupValue: prefs.themeMode, title: Text(label),
      onChanged: (value) { if (value != null) prefs.setThemeMode(value); });

  Widget _heading(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Align(alignment: AlignmentDirectional.centerStart,
      child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
  );
}
