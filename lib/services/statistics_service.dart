import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

class StatisticsService {
  static final StatisticsService _instance = StatisticsService._internal();
  factory StatisticsService() => _instance;
  StatisticsService._internal();
  
  Database? _db;
  
  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      '${dir.path}/statistics.db',
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE stats (
            id INTEGER PRIMARY KEY,
            event_type TEXT,
            event_value TEXT,
            timestamp INTEGER
          )
        ''');
      },
    );
  }
  
  Future<void> trackEvent(String type, {String? value}) async {
    await _db?.insert('stats', {
      'event_type': type,
      'event_value': value ?? '',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }
  
  Future<Map<String, dynamic>> getStatistics() async {
    final totalEvents = Sqflite.firstIntValue(
      await _db?.rawQuery('SELECT COUNT(*) FROM stats')
    ) ?? 0;
    
    final todayEvents = Sqflite.firstIntValue(
      await _db?.rawQuery('''
        SELECT COUNT(*) FROM stats 
        WHERE date(timestamp/1000, 'unixepoch') = date('now')
      ''')
    ) ?? 0;
    
    return {
      'total_events': totalEvents,
      'today_events': todayEvents,
      'last_updated': DateTime.now(),
    };
  }
  
  void dispose() {
    _db?.close();
  }
}
