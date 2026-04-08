import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

class ConversationMemory {
  static final ConversationMemory _instance = ConversationMemory._internal();
  factory ConversationMemory() => _instance;
  ConversationMemory._internal();
  
  Database? _db;
  
  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      '${dir.path}/conversations.db',
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            content TEXT,
            isUser INTEGER,
            timestamp INTEGER,
            modelName TEXT
          )
        ''');
      },
    );
  }
  
  Future<void> saveMessage(String content, bool isUser, String modelName) async {
    await _db?.insert('messages', {
      'content': content,
      'isUser': isUser ? 1 : 0,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'modelName': modelName,
    });
  }
  
  Future<List<Map<String, dynamic>>> getMessages({int limit = 50}) async {
    return await _db?.query(
      'messages',
      orderBy: 'timestamp DESC',
      limit: limit,
    ) ?? [];
  }
  
  Future<void> clearHistory() async {
    await _db?.delete('messages');
  }
  
  Future<int> getMessageCount() async {
    final result = await _db?.rawQuery('SELECT COUNT(*) as count FROM messages');
    return result?.first['count'] as int? ?? 0;
  }
  
  void dispose() {
    _db?.close();
  }
}
