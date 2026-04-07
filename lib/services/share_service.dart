import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class ShareService {
  static Future<void> shareConversation(List<Map<String, dynamic>> messages) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/conversation.txt');
    String content = 'محادثة Giant Agent X\n${DateTime.now()}\n\n';
    for (var msg in messages) {
      content += '${msg['isUser'] ? '👤' : '🤖'} (${(msg['time'] as DateTime).hour}:${(msg['time'] as DateTime).minute}):\n${msg['content']}\n\n';
    }
    await file.writeAsString(content);
    await Share.shareXFiles([XFile(file.path)], text: 'محادثة Giant Agent X');
  }
  
  static Future<void> shareAsImage(String text) async {
    await Share.share(text);
  }
}
