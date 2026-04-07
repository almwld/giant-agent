import 'package:sqflite/sqflite.dart';
import 'database_service.dart';

class SearchService {
  static Future<List<Map<String, dynamic>>> searchMessages(String query) async {
    final db = await DatabaseService.database;
    return await db.query(
      'messages',
      where: 'text LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'timestamp DESC',
    );
  }
  
  static Future<List<Map<String, dynamic>>> searchByDate(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final db = await DatabaseService.database;
    return await db.query(
      'messages',
      where: 'timestamp BETWEEN ? AND ?',
      whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
    );
  }
}
