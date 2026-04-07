import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();
  
  Database? _db;
  
  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      '${dir.path}/analytics.db',
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE events (
            id INTEGER PRIMARY KEY,
            event_type TEXT,
            event_data TEXT,
            timestamp INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE sessions (
            id INTEGER PRIMARY KEY,
            start_time INTEGER,
            end_time INTEGER,
            message_count INTEGER
          )
        ''');
      },
    );
  }
  
  Future<void> trackEvent(String eventType, {Map<String, dynamic>? data}) async {
    await _db?.insert('events', {
      'event_type': eventType,
      'event_data': data != null ? data.toString() : '',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }
  
  Future<void> startSession() async {
    await _db?.insert('sessions', {
      'start_time': DateTime.now().millisecondsSinceEpoch,
      'message_count': 0,
    });
  }
  
  Future<void> endSession(int sessionId, int messageCount) async {
    await _db?.update(
      'sessions',
      {
        'end_time': DateTime.now().millisecondsSinceEpoch,
        'message_count': messageCount,
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }
  
  Future<Map<String, dynamic>> getStats() async {
    final eventCount = Sqflite.firstIntValue(await _db?.rawQuery('SELECT COUNT(*) FROM events')) ?? 0;
    final sessionCount = Sqflite.firstIntValue(await _db?.rawQuery('SELECT COUNT(*) FROM sessions')) ?? 0;
    
    return {
      'total_events': eventCount,
      'total_sessions': sessionCount,
      'last_updated': DateTime.now(),
    };
  }
  
  void dispose() {
    _db?.close();
  }
}
