import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

class DatabaseService {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  static Future<Database> _initDB() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/giant_agent_x.db';
    
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            text TEXT,
            isUser INTEGER,
            time TEXT
          )
        ''');
      },
    );
  }

  static Future<void> saveMessage(String text, bool isUser) async {
    final db = await database;
    await db.insert('messages', {
      'text': text,
      'isUser': isUser ? 1 : 0,
      'time': DateTime.now().toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> getMessages() async {
    final db = await database;
    return await db.query('messages', orderBy: 'id DESC', limit: 200);
  }

  static Future<void> clearMessages() async {
    final db = await database;
    await db.delete('messages');
  }

  static Future<String> exportChat() async {
    final messages = await getMessages();
    final content = messages.reversed.map((m) {
      final time = DateTime.parse(m['time']);
      return '${m['isUser'] == 1 ? '👤' : '🤖'} [${time.hour}:${time.minute}]: ${m['text']}';
    }).join('\n');
    
    return '⚡ محادثة Giant Agent X - أقوى وكيل في العالم\n📅 ${DateTime.now()}\n\n$content\n\n⭐ متفوق على جميع المنافسين!';
  }
}
