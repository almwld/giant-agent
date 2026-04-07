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
        await db.execute('''
          CREATE TABLE tasks (
            id INTEGER PRIMARY KEY,
            task TEXT,
            status TEXT,
            result TEXT,
            created_at INTEGER,
            completed_at INTEGER
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
      return result.first['value'];
    }
    return null;
  }
  
  Future<List<Map<String, dynamic>>> searchMemories(String query) async {
    return await _db?.query(
      'memories',
      where: 'key LIKE ? OR value LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'timestamp DESC',
      limit: 20,
    ) ?? [];
  }
  
  Future<int> createTask(String task) async {
    return await _db?.insert('tasks', {
      'task': task,
      'status': 'pending',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }) ?? 0;
  }
  
  Future<void> completeTask(int taskId, String result) async {
    await _db?.update(
      'tasks',
      {
        'status': 'completed',
        'result': result,
        'completed_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [taskId],
    );
  }
  
  Future<List<Map<String, dynamic>>> getPendingTasks() async {
    return await _db?.query(
      'tasks',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'created_at ASC',
    ) ?? [];
  }
  
  void dispose() {
    _db?.close();
  }
}
