import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class FileUploadService {
  static Database? _db;
  
  // تهيئة قاعدة البيانات
  static Future<void> initDB() async {
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      '${dir.path}/giant_agent.db',
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE processed_files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            filename TEXT,
            content TEXT,
            analysis TEXT,
            timestamp INTEGER
          )
        ''');
      },
    );
  }
  
  // اختيار ملف
  static Future<File?> pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) {
      return File(result.files.single.path!);
    }
    return null;
  }
  
  // معالجة ملف نصي
  static Future<Map<String, dynamic>> processTextFile(File file) async {
    final content = await file.readAsString();
    final lines = content.split('\n');
    
    // تحليل النص
    final analysis = {
      'filename': file.path.split('/').last,
      'size': await file.length(),
      'lines': lines.length,
      'characters': content.length,
      'words': content.split(' ').length,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    
    // حفظ في قاعدة البيانات
    await _db?.insert('processed_files', {
      'filename': analysis['filename'],
      'content': content.length > 1000 ? content.substring(0, 1000) : content,
      'analysis': json.encode(analysis),
      'timestamp': analysis['timestamp'],
    });
    
    return analysis;
  }
  
  // معالجة ملف JSON
  static Future<Map<String, dynamic>> processJsonFile(File file) async {
    final content = await file.readAsString();
    final jsonData = json.decode(content);
    
    final analysis = {
      'filename': file.path.split('/').last,
      'size': await file.length(),
      'type': 'json',
      'keys': jsonData is Map ? jsonData.keys.length : (jsonData is List ? jsonData.length : 0),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    
    await _db?.insert('processed_files', {
      'filename': analysis['filename'],
      'content': content.length > 1000 ? content.substring(0, 1000) : content,
      'analysis': json.encode(analysis),
      'timestamp': analysis['timestamp'],
    });
    
    return analysis;
  }
  
  // معالجة ملف CSV
  static Future<Map<String, dynamic>> processCsvFile(File file) async {
    final content = await file.readAsString();
    final lines = content.split('\n');
    
    final analysis = {
      'filename': file.path.split('/').last,
      'size': await file.length(),
      'rows': lines.length,
      'columns': lines.isNotEmpty ? lines[0].split(',').length : 0,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    
    await _db?.insert('processed_files', {
      'filename': analysis['filename'],
      'content': content.length > 1000 ? content.substring(0, 1000) : content,
      'analysis': json.encode(analysis),
      'timestamp': analysis['timestamp'],
    });
    
    return analysis;
  }
  
  // الحصول على تاريخ الملفات
  static Future<List<Map<String, dynamic>>> getHistory() async {
    return await _db?.query('processed_files', orderBy: 'timestamp DESC') ?? [];
  }
  
  // مسح التاريخ
  static Future<void> clearHistory() async {
    await _db?.delete('processed_files');
  }
}
