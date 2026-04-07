import 'package:shared_preferences/shared_preferences.dart';

class OfflineMode {
  static const String _offlineKey = 'offline_mode';
  
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_offlineKey) ?? true;
  }
  
  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_offlineKey, enabled);
  }
  
  static String getOfflineMessage() {
    return '🌐 أنت في وضع عدم الاتصال\nجميع البيانات محفوظة محلياً';
  }
}
