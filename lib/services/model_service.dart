import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:file_picker/file_picker.dart';

class ModelService {
  static final ModelService _instance = ModelService._internal();
  factory ModelService() => _instance;
  ModelService._internal();
  
  List<Map<String, dynamic>> _models = [];
  String _activeModelId = '';
  bool _isInitialized = false;
  Database? _db;
  
  Future<void> init() async {
    if (_isInitialized) return;
    
    // تهيئة قاعدة البيانات
    final docsDir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      '${docsDir.path}/conversations.db',
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            role TEXT,
            content TEXT,
            timestamp INTEGER
          )
        ''');
      },
    );
    
    // البحث عن النماذج
    await scanModels();
    
    _isInitialized = true;
  }
  
  // مسح جميع مجلدات الهاتف بحثاً عن النماذج
  Future<void> scanModels() async {
    _models.clear();
    
    // قائمة المسارات للبحث
    List<String> searchPaths = [
      '/storage/emulated/0/Download/models/',
      '/sdcard/Download/models/',
      '/storage/emulated/0/Phi3Model/',
      '/storage/emulated/0/Android/data/com.example.giant_agent/files/models/',
      '/storage/emulated/0/Models/',
      '/sdcard/Models/',
    ];
    
    // البحث في كل مسار
    for (String path in searchPaths) {
      final dir = Directory(path);
      if (await dir.exists()) {
        try {
          final files = await dir.list().toList();
          for (var file in files) {
            if (file.path.endsWith('.tflite') || 
                file.path.endsWith('.onnx') || 
                file.path.endsWith('.gguf')) {
              
              final size = await File(file.path).length();
              final sizeMB = (size / 1024 / 1024).toStringAsFixed(2);
              
              _models.add({
                'id': file.path.split('/').last.replaceAll('.tflite', '').replaceAll('.onnx', '').replaceAll('.gguf', ''),
                'name': file.path.split('/').last,
                'path': file.path,
                'size': sizeMB,
                'type': file.path.split('.').last,
                'status': 'available',
                'loaded': true,
              });
            }
          }
        } catch (e) {
          print('Error scanning $path: $e');
        }
      }
    }
    
    // إضافة نموذج تجريبي إذا لم يتم العثور على نماذج
    if (_models.isEmpty) {
      _models.add({
        'id': 'builtin',
        'name': 'Built-in AI',
        'path': null,
        'size': '0',
        'type': 'builtin',
        'status': 'available',
        'loaded': true,
      });
    }
    
    _activeModelId = _models.first['id'];
  }
  
  // إضافة نموذج من ملف يختاره المستخدم
  Future<bool> addModelFromFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['tflite', 'onnx', 'gguf'],
    );
    
    if (result != null) {
      final file = File(result.files.single.path!);
      final fileName = result.files.single.name;
      
      // إنشاء مجلد النماذج إذا لم يكن موجوداً
      final modelsDir = Directory('/storage/emulated/0/Download/models/');
      if (!await modelsDir.exists()) {
        await modelsDir.create(recursive: true);
      }
      
      // نسخ الملف إلى مجلد النماذج
      final newPath = '/storage/emulated/0/Download/models/$fileName';
      await file.copy(newPath);
      
      // إعادة مسح النماذج
      await scanModels();
      
      return true;
    }
    return false;
  }
  
  // تحديث النماذج
  Future<void> refreshModels() async {
    await scanModels();
  }
  
  List<Map<String, dynamic>> getModels() {
    return _models;
  }
  
  Map<String, dynamic> getActiveModel() {
    return _models.firstWhere((m) => m['id'] == _activeModelId, orElse: () => _models.first);
  }
  
  Future<bool> switchModel(String modelId) async {
    final model = _models.firstWhere((m) => m['id'] == modelId, orElse: () => {});
    if (model.isNotEmpty) {
      _activeModelId = modelId;
      return true;
    }
    return false;
  }
  
  // حفظ رسالة
  Future<void> saveMessage(String role, String content) async {
    await _db?.insert('messages', {
      'role': role,
      'content': content,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }
  
  // توليد رد ذكي
  Future<String> generateResponse(String input) async {
    await saveMessage('user', input);
    
    final lower = input.toLowerCase();
    String response;
    
    if (lower.contains('مرحبا') || lower.contains('السلام')) {
      response = 'مرحباً! 👋 أنا Giant Agent X. كيف يمكنني مساعدتك اليوم؟';
    }
    else if (lower.contains('كيف حالك')) {
      response = 'أنا بخير، شكراً لسؤالك! 🧠 جاهز لمساعدتك في أي وقت.';
    }
    else if (lower.contains('شكرا')) {
      response = 'العفو! 🤝 دائماً في خدمتك.';
    }
    else if (lower.contains('وداعا')) {
      response = 'وداعاً! 👋 سعدت بمساعدتك.';
    }
    else if (lower.contains('كود') || lower.contains('code')) {
      response = await _generateCode(input);
    }
    else if (lower.contains('موقع') || lower.contains('site')) {
      response = await _generateWebsite(input);
    }
    else if (lower.contains('حلل')) {
      response = _analyzeText(input);
    }
    else if (lower.contains('+') || lower.contains('-') || lower.contains('*') || lower.contains('/')) {
      response = _calculate(input);
    }
    else if (lower.contains('مساعدة') || lower.contains('help')) {
      response = _getHelp();
    }
    else {
      response = _getGeneralResponse(input);
    }
    
    await saveMessage('agent', response);
    return response;
  }
  
  Future<String> _generateCode(String input) async {
    return '''
```dart
// كود تم إنشاؤه بواسطة Giant Agent X
void main() {
  print("Hello from Giant Agent X!");
  print("مرحباً من الوكيل العملاق!");
}
```
''';
  }
  
  Future<String> _generateWebsite(String input) async {
    return '''
```html
<!DOCTYPE html>
<html>
<head><title>Giant Agent</title></head>
<body><h1>Hello from Giant Agent X!</h1></body>
</html>
```
''';
  }
  
  String _analyzeText(String input) {
    final text = input.replaceAll('حلل', '').trim();
    if (text.isEmpty) return 'الرجاء إدخال النص للتحليل';
    return '📊 تم تحليل النص بنجاح.\nالطول: ${text.length} حرف\nالكلمات: ${text.split(' ').length} كلمة';
  }
  
  String _calculate(String input) {
    try {
      if (input.contains('+')) {
        final parts = input.split('+');
        return 'النتيجة: ${double.parse(parts[0]) + double.parse(parts[1])}';
      }
    } catch (e) {}
    return 'النتيجة: خطأ في العملية';
  }
  
  String _getHelp() {
    return '''
📚 **الأوامر المتاحة:**
• مرحبا - تحية
• كيف حالك - السؤال عن الحال
• اكتب كود - توليد كود
• أنشئ موقعاً - إنشاء HTML
• حلل النص: ... - تحليل نص
• 5+3 - عمليات حسابية
''';
  }
  
  String _getGeneralResponse(String input) {
    final responses = [
      'سؤال جيد! كيف يمكنني مساعدتك بشكل أفضل؟',
      'أفهم ما تقصده. هل تريد معرفة المزيد؟',
      'هذا مثير للاهتمام! أخبرني أكثر.',
    ];
    return responses[Random().nextInt(responses.length)];
  }
  
  void dispose() {
    _db?.close();
  }
}
