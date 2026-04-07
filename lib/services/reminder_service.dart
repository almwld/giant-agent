import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'notification_service.dart';

class ReminderService {
  static final ReminderService _instance = ReminderService._internal();
  factory ReminderService() => _instance;
  ReminderService._internal();
  
  Database? _db;
  
  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      '${dir.path}/reminders.db',
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE reminders (
            id INTEGER PRIMARY KEY,
            title TEXT,
            description TEXT,
            reminder_time INTEGER,
            is_completed INTEGER,
            created_at INTEGER
          )
        ''');
      },
    );
  }
  
  Future<int> addReminder(String title, String description, DateTime time) async {
    return await _db?.insert('reminders', {
      'title': title,
      'description': description,
      'reminder_time': time.millisecondsSinceEpoch,
      'is_completed': 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }) ?? 0;
  }
  
  Future<List<Map<String, dynamic>>> getReminders() async {
    return await _db?.query('reminders', orderBy: 'reminder_time ASC') ?? [];
  }
  
  Future<List<Map<String, dynamic>>> getActiveReminders() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return await _db?.query(
      'reminders',
      where: 'reminder_time > ? AND is_completed = 0',
      whereArgs: [now],
      orderBy: 'reminder_time ASC',
    ) ?? [];
  }
  
  Future<void> completeReminder(int id) async {
    await _db?.update(
      'reminders',
      {'is_completed': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  
  Future<void> deleteReminder(int id) async {
    await _db?.delete('reminders', where: 'id = ?', whereArgs: [id]);
  }
  
  Future<void> checkReminders() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final reminders = await _db?.query(
      'reminders',
      where: 'reminder_time <= ? AND is_completed = 0',
      whereArgs: [now],
    ) ?? [];
    
    for (var reminder in reminders) {
      await NotificationService().showNotification(
        reminder['title'],
        reminder['description'],
      );
      await completeReminder(reminder['id']);
    }
  }
  
  void dispose() {
    _db?.close();
  }
}
