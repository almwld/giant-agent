import 'dart:io';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class BackupService {
  static Future<void> backupConversations(Database db) async {
    final conversations = await db.query('messages');
    final backup = {
      'timestamp': DateTime.now().toIso8601String(),
      'version': '1.0',
      'conversations': conversations,
    };
    
    final output = await getTemporaryDirectory();
    final file = File('${output.path}/backup_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(json.encode(backup));
    
    await Share.shareXFiles([XFile(file.path)], text: 'Conversations Backup');
  }
  
  static Future<void> restoreBackup(String filePath, Database db) async {
    final file = File(filePath);
    final content = await file.readAsString();
    final backup = json.decode(content);
    
    await db.delete('messages');
    
    for (var msg in backup['conversations']) {
      await db.insert('messages', msg);
    }
  }
}
