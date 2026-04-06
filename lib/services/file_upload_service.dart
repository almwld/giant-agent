import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../nuclear/processors/mass_processor.dart';
import '../nuclear/database/giant_database.dart';

class FileUploadService {
  final GiantDatabase _db = GiantDatabase();
  
  // اختيار ملف من الهاتف
  static Future<File?> pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    
    if (result != null) {
      return File(result.files.single.path!);
    }
    return null;
  }
  
  // اختيار ملفات متعددة
  static Future<List<File>> pickMultipleFiles() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(allowMultiple: true);
    
    if (result != null) {
      return result.paths.map((p) => File(p!)).toList();
    }
    return [];
  }
  
  // معالجة ملف نصي
  Future<Map<String, dynamic>> processTextFile(File file) async {
    final content = await file.readAsString();
    final lines = content.split('\n');
    
    final processor = MassTextProcessor();
    
    for (var line in lines) {
      if (line.trim().isNotEmpty) {
        processor.addText(line);
      }
    }
    
    final results = await processor.processAll();
    
    // حفظ في قاعدة البيانات
    for (var result in results) {
      await _db.insertText({
        'content': result['text'],
        'length': result['analysis']['length'],
        'word_count': result['analysis']['word_count'],
        'sentiment': _getSentimentScore(result['analysis']['sentiment']),
        'language': result['analysis']['language'],
        'keywords': result['analysis']['keywords'],
        'user_id': 'file_upload',
      });
    }
    
    // حفظ معلومات الملف
    final fileSize = await file.length();
    final fileInfo = {
      'filename': path.basename(file.path),
      'filepath': file.path,
      'size': fileSize,
      'type': 'text',
      'processed': 1,
      'uploaded_at': DateTime.now().millisecondsSinceEpoch,
    };
    
    return {
      'success': true,
      'total_lines': lines.length,
      'total_processed': results.length,
      'file_info': fileInfo,
      'results': results,
    };
  }
  
  // معالجة ملف JSON
  Future<Map<String, dynamic>> processJsonFile(File file) async {
    final content = await file.readAsString();
    final jsonData = json.decode(content);
    
    List<dynamic> texts = [];
    if (jsonData is List) {
      texts = jsonData;
    } else if (jsonData is Map && jsonData.containsKey('texts')) {
      texts = jsonData['texts'];
    } else {
      texts = [jsonData];
    }
    
    final processor = MassTextProcessor();
    
    for (var item in texts) {
      final text = item.toString();
      processor.addText(text);
    }
    
    final results = await processor.processAll();
    
    // حفظ في قاعدة البيانات
    for (var result in results) {
      await _db.insertText({
        'content': result['text'],
        'length': result['analysis']['length'],
        'word_count': result['analysis']['word_count'],
        'sentiment': _getSentimentScore(result['analysis']['sentiment']),
        'language': result['analysis']['language'],
        'keywords': result['analysis']['keywords'],
        'user_id': 'json_upload',
      });
    }
    
    return {
      'success': true,
      'total_items': texts.length,
      'total_processed': results.length,
      'results': results,
    };
  }
  
  // معالجة ملف CSV
  Future<Map<String, dynamic>> processCsvFile(File file) async {
    final content = await file.readAsString();
    final lines = content.split('\n');
    
    final processor = MassTextProcessor();
    
    for (var line in lines) {
      final cells = line.split(',');
      for (var cell in cells) {
        if (cell.trim().isNotEmpty) {
          processor.addText(cell.trim());
        }
      }
    }
    
    final results = await processor.processAll();
    
    for (var result in results) {
      await _db.insertText({
        'content': result['text'],
        'length': result['analysis']['length'],
        'word_count': result['analysis']['word_count'],
        'sentiment': _getSentimentScore(result['analysis']['sentiment']),
        'language': result['analysis']['language'],
        'keywords': result['analysis']['keywords'],
        'user_id': 'csv_upload',
      });
    }
    
    return {
      'success': true,
      'total_cells': processor.count,
      'total_processed': results.length,
      'results': results,
    };
  }
  
  double _getSentimentScore(String sentiment) {
    switch(sentiment) {
      case 'positive': return 0.9;
      case 'negative': return 0.1;
      default: return 0.5;
    }
  }
  
  // الحصول على إحصائيات قاعدة البيانات
  Future<Map<String, dynamic>> getDatabaseStats() async {
    return await _db.getQuickStats();
  }
  
  // تصدير قاعدة البيانات
  Future<String> exportDatabase() async {
    return await _db.exportDatabase();
  }
}
