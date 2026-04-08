import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ConversationService {
  static Future<void> saveConversation(List<Map<String, dynamic>> messages) async {
    final dir = await getExternalStorageDirectory();
    final file = File('${dir?.path}/conversation_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(json.encode(messages));
  }
  
  static Future<List<Map<String, dynamic>>> loadConversation(String path) async {
    final file = File(path);
    final content = await file.readAsString();
    return List<Map<String, dynamic>>.from(json.decode(content));
  }
  
  static Future<void> exportAsText(List<Map<String, dynamic>> messages) async {
    final dir = await getExternalStorageDirectory();
    final content = StringBuffer();
    content.writeln('محادثة Giant Agent X');
    content.writeln('=' * 40);
    content.writeln();
    
    for (var msg in messages) {
      final prefix = msg['isUser'] ? '👤 المستخدم' : '🤖 Giant Agent X';
      final time = (msg['time'] as DateTime).hour.toString().padLeft(2, '0') + ':' + (msg['time'] as DateTime).minute.toString().padLeft(2, '0');
      content.writeln('[$time] $prefix:');
      content.writeln(msg['content']);
      content.writeln();
    }
    
    final file = File('${dir?.path}/conversation_export_${DateTime.now().millisecondsSinceEpoch}.txt');
    await file.writeAsString(content.toString());
    await Share.shareXFiles([XFile(file.path)], text: 'تصدير المحادثة');
  }
}
