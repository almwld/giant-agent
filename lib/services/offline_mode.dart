import 'package:shared_preferences/shared_preferences.dart';

class OfflineMode {
  static final OfflineMode _instance = OfflineMode._internal();
  factory OfflineMode() => _instance;
  OfflineMode._internal();
  
  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('offline_mode') ?? true;
  }
  
  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('offline_mode', enabled);
  }
  
  String getOfflineMessage() {
    return '🌐 **وضع عدم الاتصال**\n\nالتطبيق يعمل محلياً بالكامل.\nجميع البيانات مخزنة على جهازك.';
  }
}
