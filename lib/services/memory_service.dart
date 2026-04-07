import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

class MemoryService {
  static final MemoryService _instance = MemoryService._internal();
  factory MemoryService() => _instance;
  MemoryService._internal();
  
  Database? _db;
  
  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      '${dir.path}/giant_memory.db',
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE conversations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_input TEXT,
            agent_response TEXT,
            timestamp INTEGER,
            context TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE user_preferences (
            key TEXT PRIMARY KEY,
            value TEXT,
            updated_at INTEGER
          )
        ''');
      },
    );
  }
  
  Future<void> saveConversation(String userInput, String agentResponse, {String? context}) async {
    await _db?.insert('conversations', {
      'user_input': userInput,
      'agent_response': agentResponse,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'context': context ?? 'general',
    });
  }
  
  Future<List<Map<String, dynamic>>> getRecentConversations({int limit = 10}) async {
    return await _db?.query(
      'conversations',
      orderBy: 'timestamp DESC',
      limit: limit,
    ) ?? [];
  }
  
  Future<String?> getSimilarResponse(String userInput) async {
    // بحث بسيط عن رد مشابه
    final results = await _db?.query(
      'conversations',
      where: 'user_input LIKE ?',
      whereArgs: ['%$userInput%'],
      limit: 1,
    );
    
    if (results != null && results.isNotEmpty) {
      return results.first['agent_response'];
    }
    return null;
  }
  
  Future<void> savePreference(String key, String value) async {
    await _db?.insert(
      'user_preferences',
      {
        'key': key,
        'value': value,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  
  Future<String?> getPreference(String key) async {
    final result = await _db?.query(
      'user_preferences',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (result != null && result.isNotEmpty) {
      return result.first['value'];
    }
    return null;
  }
  
  Future<void> clearMemory() async {
    await _db?.delete('conversations');
  }
  
  void dispose() {
    _db?.close();
  }
}
