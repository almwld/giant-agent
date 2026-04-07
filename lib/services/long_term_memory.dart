import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

class LongTermMemory {
  static final LongTermMemory _instance = LongTermMemory._internal();
  factory LongTermMemory() => _instance;
  LongTermMemory._internal();
  
  Database? _db;
  
  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      '${dir.path}/long_term_memory.db',
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE memories (
            id INTEGER PRIMARY KEY,
            key TEXT,
            value TEXT,
            timestamp INTEGER,
            importance INTEGER
          )
        ''');
      },
    );
  }
  
  Future<void> saveMemory(String key, String value, {int importance = 1}) async {
    await _db?.insert('memories', {
      'key': key,
      'value': value,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'importance': importance,
    });
  }
  
  Future<String?> recallMemory(String key) async {
    final result = await _db?.query(
      'memories',
      where: 'key = ?',
      whereArgs: [key],
      orderBy: 'importance DESC',
      limit: 1,
    );
    if (result != null && result.isNotEmpty) {
      final value = result.first['value'];
      return value.toString();
    }
    return null;
  }
  
  void dispose() {
    _db?.close();
  }
}
