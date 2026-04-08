import 'package:shared_preferences/shared_preferences.dart';

class StatsService {
  static final StatsService _instance = StatsService._internal();
  factory StatsService() => _instance;
  StatsService._internal();
  
  Future<void> incrementMessageCount() async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt('total_messages') ?? 0;
    await prefs.setInt('total_messages', count + 1);
  }
  
  Future<int> getTotalMessages() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('total_messages') ?? 0;
  }
  
  Future<void> incrementModelSwitches() async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt('model_switches') ?? 0;
    await prefs.setInt('model_switches', count + 1);
  }
  
  Future<Map<String, dynamic>> getAllStats() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'total_messages': prefs.getInt('total_messages') ?? 0,
      'model_switches': prefs.getInt('model_switches') ?? 0,
      'first_launch': prefs.getString('first_launch') ?? DateTime.now().toIso8601String(),
    };
  }
}
