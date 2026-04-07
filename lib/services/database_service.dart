import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

class DatabaseService {
  static Database? _db;
  
  static Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase('${dir.path}/chat_history.db', version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            text TEXT,
            isUser INTEGER,
            timestamp INTEGER
          )
        ''');
      });
    return _db!;
  }
  
  static Future<void> saveMessage(String text, bool isUser) async {
    final db = await database;
    await db.insert('messages', {
      'text': text,
      'isUser': isUser ? 1 : 0,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }
  
  static Future<List<Map<String, dynamic>>> getMessages() async {
    final db = await database;
    return await db.query('messages', orderBy: 'timestamp ASC');
  }
  
  static Future<void> clearMessages() async {
    final db = await database;
    await db.delete('messages');
  }
  
  static Future<String> exportToText() async {
    final messages = await getMessages();
    String content = 'محادثة Giant Agent X\n${DateTime.now()}\n\n';
    for (var msg in messages) {
      content += '${msg['isUser'] == 1 ? '👤' : '🤖'} (${DateTime.fromMillisecondsSinceEpoch(msg['timestamp']).hour}:${DateTime.fromMillisecondsSinceEpoch(msg['timestamp']).minute}):\n${msg['text']}\n\n';
    }
    return content;
  }
}
