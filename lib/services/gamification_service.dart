import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

class GamificationService {
  static final GamificationService _instance = GamificationService._internal();
  factory GamificationService() => _instance;
  GamificationService._internal();
  
  Database? _db;
  int _points = 0;
  int _level = 1;
  List<String> _achievements = [];
  
  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      '${dir.path}/gamification.db',
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE user_stats (
            id INTEGER PRIMARY KEY,
            points INTEGER,
            level INTEGER,
            achievements TEXT
          )
        ''');
      },
    );
    await _loadStats();
  }
  
  Future<void> _loadStats() async {
    final result = await _db?.query('user_stats', limit: 1);
    if (result != null && result.isNotEmpty) {
      _points = result.first['points'] ?? 0;
      _level = result.first['level'] ?? 1;
      _achievements = (result.first['achievements'] as String?)?.split(',') ?? [];
    }
  }
  
  Future<void> addPoints(int points, String reason) async {
    _points += points;
    await _checkLevelUp();
    await _db?.insert('user_stats', {
      'points': _points,
      'level': _level,
      'achievements': _achievements.join(','),
    });
  }
  
  Future<void> _checkLevelUp() async {
    final newLevel = 1 + (_points ~/ 100);
    if (newLevel > _level) {
      _level = newLevel;
      await unlockAchievement('level_$_level');
    }
  }
  
  Future<void> unlockAchievement(String achievementId) async {
    if (!_achievements.contains(achievementId)) {
      _achievements.add(achievementId);
      await addPoints(50, 'فتح إنجاز: $achievementId');
    }
  }
  
  Map<String, dynamic> getStats() {
    return {
      'points': _points,
      'level': _level,
      'achievements': _achievements.length,
      'next_level_points': (_level * 100) - _points,
    };
  }
  
  void dispose() {
    _db?.close();
  }
}
