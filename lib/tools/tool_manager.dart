import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

class ToolManager {
  static final ToolManager _instance = ToolManager._internal();
  factory ToolManager() => _instance;
  ToolManager._internal();
  
  final Map<String, Function> _tools = {};
  
  void registerTools() {
    _tools['calculator'] = _calculator;
    _tools['file_writer'] = _fileWriter;
    _tools['file_reader'] = _fileReader;
    _tools['web_search'] = _webSearch;
    _tools['code_executor'] = _codeExecutor;
    _tools['reminder'] = _reminder;
    _tools['translator'] = _translator;
    _tools['summarizer'] = _summarizer;
  }
  
  Future<String> executeTool(String toolName, Map<String, dynamic> params) async {
    if (_tools.containsKey(toolName)) {
      try {
        return await _tools[toolName]!(params);
      } catch (e) {
        return 'خطأ في تنفيذ الأداة $toolName: $e';
      }
    }
    return 'الأداة $toolName غير موجودة';
  }
  
  // 1. آلة حاسبة
  Future<String> _calculator(Map<String, dynamic> params) async {
    final expression = params['expression'] as String;
    try {
      final result = _evaluateExpression(expression);
      return 'نتيجة العملية: $result';
    } catch (e) {
      return 'خطأ في الحساب: $e';
    }
  }
  
  double _evaluateExpression(String expr) {
    // تبسيط: معالجة العمليات الأساسية
    if (expr.contains('+')) {
      final parts = expr.split('+');
      return double.parse(parts[0]) + double.parse(parts[1]);
    } else if (expr.contains('-')) {
      final parts = expr.split('-');
      return double.parse(parts[0]) - double.parse(parts[1]);
    } else if (expr.contains('*')) {
      final parts = expr.split('*');
      return double.parse(parts[0]) * double.parse(parts[1]);
    } else if (expr.contains('/')) {
      final parts = expr.split('/');
      return double.parse(parts[0]) / double.parse(parts[1]);
    }
    return 0;
  }
  
  // 2. كتابة ملف
  Future<String> _fileWriter(Map<String, dynamic> params) async {
    final fileName = params['filename'] as String;
    final content = params['content'] as String;
    final dir = await getExternalStorageDirectory();
    final file = File('${dir?.path}/$fileName');
    await file.writeAsString(content);
    return '✅ تم إنشاء الملف: ${file.path}';
  }
  
  // 3. قراءة ملف
  Future<String> _fileReader(Map<String, dynamic> params) async {
    final fileName = params['filename'] as String;
    final dir = await getExternalStorageDirectory();
    final file = File('${dir?.path}/$fileName');
    if (await file.exists()) {
      final content = await file.readAsString();
      return 'محتوى الملف:\n$content';
    }
    return 'الملف غير موجود';
  }
  
  // 4. بحث ويب (محاكاة)
  Future<String> _webSearch(Map<String, dynamic> params) async {
    final query = params['query'] as String;
    // محاكاة بحث (يمكن ربطها بـ API حقيقي)
    return '🔍 نتائج البحث عن "$query":\n• نتيجة 1\n• نتيجة 2\n• نتيجة 3';
  }
  
  // 5. تنفيذ كود
  Future<String> _codeExecutor(Map<String, dynamic> params) async {
    final code = params['code'] as String;
    final language = params['language'] as String;
    // محاكاة تنفيذ الكود
    return '✅ تم تنفيذ كود $language:\n$code';
  }
  
  // 6. تذكير
  Future<String> _reminder(Map<String, dynamic> params) async {
    final message = params['message'] as String;
    final time = params['time'] as String;
    return '✅ تم حفظ التذكير: "$message" في الساعة $time';
  }
  
  // 7. ترجمة
  Future<String> _translator(Map<String, dynamic> params) async {
    final text = params['text'] as String;
    final targetLang = params['target'] as String;
    // محاكاة ترجمة
    return '🌐 الترجمة إلى $targetLang:\n$text (محاكاة)';
  }
  
  // 8. تلخيص
  Future<String> _summarizer(Map<String, dynamic> params) async {
    final text = params['text'] as String;
    final summary = text.length > 100 ? '${text.substring(0, 100)}...' : text;
    return '📝 الملخص:\n$summary';
  }
  
  List<String> getAvailableTools() {
    return _tools.keys.toList();
  }
}
