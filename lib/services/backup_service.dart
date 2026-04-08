import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

class BackupService {
  static Future<void> backupDatabase(Database db) async {
    final dir = await getExternalStorageDirectory();
    final backupPath = '${dir?.path}/backup_${DateTime.now().millisecondsSinceEpoch}.db';
    
    // نسخ قاعدة البيانات
    final dbPath = await getDatabasesPath();
    final dbFile = File('$dbPath/conversations.db');
    await dbFile.copy(backupPath);
    
    await Share.shareXFiles([XFile(backupPath)], text: 'نسخة احتياطية للمحادثات');
  }
  
  static Future<void> restoreDatabase(String filePath, Database db) async {
    final dbPath = await getDatabasesPath();
    final targetFile = File('$dbPath/conversations.db');
    await File(filePath).copy(targetFile.path);
  }
}
