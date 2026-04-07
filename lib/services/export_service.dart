import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

class ExportService {
  static Future<void> exportAsPdf(List<Map<String, dynamic>> messages, String title) async {
    final pdf = pw.Document();
    
    pdf.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text(title, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 20),
          ...messages.map((msg) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                children: [
                  pw.Text(
                    msg['isUser'] ? '👤 User' : '🤖 Agent',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      color: msg['isUser'] ? PdfColors.blue : PdfColors.green,
                    ),
                  ),
                  pw.Spacer(),
                  pw.Text(
                    '${(msg['time'] as DateTime).hour}:${(msg['time'] as DateTime).minute}',
                    style: pw.TextStyle(fontSize: 10, color: PdfColors.grey),
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: msg['isUser'] ? PdfColors.blue100 : PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Text(msg['content']),
              ),
              pw.SizedBox(height: 12),
            ],
          )),
        ],
      ),
    );
    
    final output = await getTemporaryDirectory();
    final file = File('${output.path}/chat_export_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await pdf.save());
    
    await Share.shareXFiles([XFile(file.path)], text: 'Chat Export');
  }
  
  static Future<void> exportAsText(List<Map<String, dynamic>> messages) async {
    final buffer = StringBuffer();
    buffer.writeln('Chat Export - ${DateTime.now()}');
    buffer.writeln('=' * 50);
    buffer.writeln();
    
    for (var msg in messages) {
      final prefix = msg['isUser'] ? '👤 User' : '🤖 Agent';
      final time = '${(msg['time'] as DateTime).hour}:${(msg['time'] as DateTime).minute}';
      buffer.writeln('[$time] $prefix:');
      buffer.writeln(msg['content']);
      buffer.writeln();
    }
    
    final output = await getTemporaryDirectory();
    final file = File('${output.path}/chat_export_${DateTime.now().millisecondsSinceEpoch}.txt');
    await file.writeAsString(buffer.toString());
    
    await Share.shareXFiles([XFile(file.path)], text: 'Chat Export');
  }
}
