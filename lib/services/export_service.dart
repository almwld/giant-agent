import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

class ExportService {
  
  static Future<void> exportConversationAsMarkdown(List<Map<String, dynamic>> messages) async {
    final dir = await getExternalStorageDirectory();
    final file = File('${dir?.path}/conversation_${DateTime.now().millisecondsSinceEpoch}.md');
    
    final content = StringBuffer();
    content.writeln('# محادثة Giant Agent X');
    content.writeln('**التاريخ:** ${DateTime.now()}');
    content.writeln('**عدد الرسائل:** ${messages.length}');
    content.writeln('\n---\n');
    
    for (var msg in messages) {
      final prefix = msg['isUser'] ? '**👤 المستخدم:**' : '**🤖 Giant Agent X:**';
      content.writeln('$prefix\n${msg['content']}\n');
    }
    
    await file.writeAsString(content.toString());
    await Share.shareXFiles([XFile(file.path)], text: 'تصدير المحادثة');
  }
  
  static Future<void> exportAsJson(List<Map<String, dynamic>> messages) async {
    final dir = await getExternalStorageDirectory();
    final file = File('${dir?.path}/conversation_${DateTime.now().millisecondsSinceEpoch}.json');
    
    final exportData = {
      'export_date': DateTime.now().toIso8601String(),
      'app_version': '4.0.0',
      'total_messages': messages.length,
      'conversations': messages.map((msg) => {
        'role': msg['isUser'] ? 'user' : 'agent',
        'content': msg['content'],
        'timestamp': (msg['time'] as DateTime).toIso8601String(),
      }).toList(),
    };
    
    await file.writeAsString(exportData.toString());
    await Share.shareXFiles([XFile(file.path)], text: 'تصدير JSON');
  }
}
