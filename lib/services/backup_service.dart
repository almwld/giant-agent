import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'database_service.dart';

class BackupService {
  static Future<void> backup() async {
    final messages = await DatabaseService.getMessages();
    final backup = {
      'date': DateTime.now().toIso8601String(),
      'version': '4.0.0',
      'messages': messages,
    };
    final dir = await getExternalStorageDirectory();
    final file = File('${dir?.path}/backup_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(json.encode(backup));
    await Share.shareXFiles([XFile(file.path)], text: 'نسخة احتياطية للمحادثات');
  }
  
  static Future<void> restore(String filePath) async {
    final file = File(filePath);
    final content = await file.readAsString();
    final backup = json.decode(content);
    await DatabaseService.clearMessages();
    for (var msg in backup['messages']) {
      await DatabaseService.saveMessage(msg['text'], msg['isUser'] == 1);
    }
  }
}
