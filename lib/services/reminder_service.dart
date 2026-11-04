import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'notification_service.dart';

class ReminderService {
  static final ReminderService _instance = ReminderService._internal();
  factory ReminderService() => _instance;
  ReminderService._internal();
  
  Database? _db;
  Future<void>? _opening;
  Timer? _timer;
  bool _checking = false;
  
  Future<void> init() async {
    if (_db == null) {
      _opening ??= _open();
      try {
        await _opening;
      } catch (_) {
        _opening = null;
        rethrow;
      }
    }
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      checkReminders();
    });
    await checkReminders();
  }

  Future<void> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      '${dir.path}/reminders.db',
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE reminders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            description TEXT NOT NULL,
            reminder_time INTEGER NOT NULL,
            is_completed INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX reminders_due ON reminders(is_completed, reminder_time)');
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
    if (_db == null || _checking) return;
    _checking = true;
    try {
    final now = DateTime.now().millisecondsSinceEpoch;
    final reminders = await _db?.query(
      'reminders',
      where: 'reminder_time <= ? AND is_completed = 0',
      whereArgs: [now],
    ) ?? [];
    
    for (var reminder in reminders) {
      final delivered = await NotificationService().showNotification(
        reminder['title'],
        reminder['description'],
        id: reminder['id'] as int,
      );
      if (delivered) {
        await completeReminder(reminder['id'] as int);
      }
    }
    } finally {
      _checking = false;
    }
  }

  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    await _db?.close();
    _db = null;
    _opening = null;
  }
}
