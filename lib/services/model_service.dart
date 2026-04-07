import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'python/python_executor.dart';

class ModelService {
  static final ModelService _instance = ModelService._internal();
  factory ModelService() => _instance;
  ModelService._internal();
  
  List<Map<String, dynamic>> _models = [];
  String _activeModelId = '';
  final PythonExecutor _python = PythonExecutor();
  
  Future<void> init() async {
    await _scanModels();
  }
  
  Future<void> _scanModels() async {
    _models.clear();
    
    List<String> paths = [
      '/storage/emulated/0/Download/models/',
      '/sdcard/Download/models/',
    ];
    
    for (String path in paths) {
      Directory dir = Directory(path);
      if (await dir.exists()) {
        try {
          List<FileSystemEntity> files = await dir.list().toList();
          for (var file in files) {
            String fileName = file.path.split('/').last;
            if (fileName.endsWith('.tflite') || fileName.endsWith('.onnx') || fileName.endsWith('.gguf')) {
              File modelFile = File(file.path);
              int size = await modelFile.length();
              _models.add({
                'id': fileName,
                'name': fileName,
                'path': file.path,
                'size': (size / 1024 / 1024).toStringAsFixed(2),
                'type': fileName.split('.').last,
              });
            }
          }
        } catch (e) {}
      }
    }
    
    _models.add({
      'id': 'builtin',
      'name': 'Built-in AI',
      'path': null,
      'size': '0',
      'type': 'builtin',
    });
    
    if (_activeModelId.isEmpty && _models.isNotEmpty) {
      _activeModelId = _models.first['id'];
    }
  }
  
  Future<void> refreshModels() async {
    await _scanModels();
  }
  
  Future<bool> addModelFromFile() async {
    try {
      PermissionStatus status = await Permission.storage.request();
      if (!status.isGranted) return false;
      
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['tflite', 'onnx', 'gguf'],
      );
      
      if (result != null) {
        String sourcePath = result.files.single.path!;
        String fileName = result.files.single.name;
        
        Directory modelsDir = Directory('/storage/emulated/0/Download/models/');
        if (!await modelsDir.exists()) {
          await modelsDir.create(recursive: true);
        }
        
        String destPath = '/storage/emulated/0/Download/models/$fileName';
        await File(sourcePath).copy(destPath);
        await _scanModels();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
  
  List<Map<String, dynamic>> getModels() => _models;
  
  Map<String, dynamic> getActiveModel() {
    if (_models.isEmpty) {
      return {'id': 'builtin', 'name': 'Built-in AI', 'size': '0', 'type': 'builtin'};
    }
    return _models.firstWhere((m) => m['id'] == _activeModelId, orElse: () => _models.first);
  }
  
  Future<bool> switchModel(String modelId) async {
    Map<String, dynamic>? model = _models.firstWhere((m) => m['id'] == modelId, orElse: () => {});
    if (model.isNotEmpty) {
      _activeModelId = modelId;
      return true;
    }
    return false;
  }
  
  // الردود الذكية مع دعم Python
  Future<String> generateResponse(String input) async {
    String lower = input.toLowerCase();
    
    // مهام Python المتقدمة
    if (lower.contains('تحليل بيانات') || lower.contains('statistics')) {
      String numbersText = input.replaceAll(RegExp(r'[^0-9,\s]'), '');
      List<num> numbers = numbersText.split(',').map((e) => num.tryParse(e.trim()) ?? 0).toList();
      numbers.removeWhere((n) => n == 0);
      if (numbers.isEmpty) numbers = [10, 20, 30, 40, 50];
      return await _python.createDataAnalyzer(numbers);
    }
    
    if (lower.contains('تطبيق فلاسك') || lower.contains('flask')) {
      String appName = _extractName(input, 'تطبيق فلاسك');
      return await _python.createFlaskApp(appName);
    }
    
    if (lower.contains('تحليل نص') || lower.contains('nlp')) {
      String text = input.replaceAll(RegExp(r'تحليل نص|nlp'), '').trim();
      if (text.isEmpty) text = 'الذكاء الاصطناعي هو مستقبل التكنولوجيا';
      return await _python.analyzeTextWithNLP(text);
    }
    
    if (lower.contains('تعلم آلة') || lower.contains('machine learning')) {
      return await _python.createAndTrainModel();
    }
    
    if (lower.contains('api') || lower.contains('fastapi')) {
      String apiName = _extractName(input, 'api');
      return await _python.createFastAPI(apiName);
    }
    
    if (lower.contains('أتمتة') || lower.contains('automation')) {
      List<String> tasks = ['تحليل بيانات', 'معالجة نصوص', 'توليد تقرير', 'إرسال إشعار'];
      return await _python.automateTasks(tasks);
    }
    
    // الأوامر الأساسية
    if (lower.contains('مرحبا')) {
      return 'مرحباً! 👋 أنا Giant Agent X\nأستطيع تنفيذ مهام Python متقدمة:\n• تحليل بيانات 📊\n• تطبيقات Flask 🌐\n• تحليل نصوص NLP 📝\n• تعلم آلة 🧠\n• APIs 🚀\n• أتمتة المهام ⚡\n\nماذا تريد أن نفعل؟';
    }
    
    if (lower.contains('كود') || lower.contains('code')) {
      return await _generatePythonCode(input);
    }
    
    if (lower.contains('حلل')) {
      String text = input.replaceAll('حلل', '').trim();
      return await _python.analyzeTextWithNLP(text);
    }
    
    if (lower.contains('+') || lower.contains('-') || lower.contains('*') || lower.contains('/')) {
      return _calculate(input);
    }
    
    return _getGeneralResponse(input);
  }
  
  Future<String> _generatePythonCode(String input) async {
    String task = input.replaceAll(RegExp(r'كود|code'), '').trim();
    if (task.isEmpty) task = 'تحليل البيانات';
    
    String code = '''
# كود Python تم إنشاؤه بواسطة Giant Agent X
# المهمة: $task
# التاريخ: ${DateTime.now()}

import json
import pandas as pd
import numpy as np
from datetime import datetime

def main():
    print("🚀 Giant Agent X - Python Executor")
    print("=" * 40)
    print(f"📋 المهمة: $task")
    print(f"📅 الوقت: {datetime.now()}")
    
    # مثال: تحليل بيانات
    data = [10, 20, 30, 40, 50]
    analysis = {
        'sum': sum(data),
        'average': sum(data) / len(data),
        'max': max(data),
        'min': min(data)
    }
    
    print("\\n📊 نتائج التحليل:")
    for key, value in analysis.items():
        print(f"  • {key}: {value}")
    
    print("\\n✅ تم تنفيذ الكود بنجاح!")

if __name__ == "__main__":
    main()
''';
    
    return '''
💻 **كود Python تم إنشاؤه:**

```python
$code
```

✅ يمكنك تشغيل الكود مباشرة في Python
📦 المكتبات المطلوبة: pandas, numpy
''';
  }
  
  String _calculate(String input) {
    try {
      if (input.contains('+')) {
        List<String> parts = input.split('+');
        double a = double.parse(parts[0].trim());
        double b = double.parse(parts[1].trim());
        return '🧮 النتيجة: ${a + b}';
      } else if (input.contains('-')) {
        List<String> parts = input.split('-');
        double a = double.parse(parts[0].trim());
        double b = double.parse(parts[1].trim());
        return '🧮 النتيجة: ${a - b}';
      } else if (input.contains('*')) {
        List<String> parts = input.split('*');
        double a = double.parse(parts[0].trim());
        double b = double.parse(parts[1].trim());
        return '🧮 النتيجة: ${a * b}';
      } else if (input.contains('/')) {
        List<String> parts = input.split('/');
        double a = double.parse(parts[0].trim());
        double b = double.parse(parts[1].trim());
        if (b == 0) return 'لا يمكن القسمة على صفر';
        return '🧮 النتيجة: ${a / b}';
      }
    } catch (e) {}
    return 'خطأ في العملية الحسابية';
  }
  
  String _extractName(String input, String keyword) {
    String name = input.replaceAll(RegExp(r'$keyword|api|تطبيق'), '').trim();
    if (name.isEmpty) return 'my_app_${DateTime.now().millisecondsSinceEpoch}';
    return name.replaceAll(' ', '_');
  }
  
  String _getGeneralResponse(String input) {
    List<String> responses = [
      'سؤال جيد! كيف يمكنني مساعدتك باستخدام Python؟',
      'أستطيع تنفيذ مهام Python متقدمة مثل تحليل البيانات وتعلم الآلة',
      'هل تريد إنشاء تطبيق Flask أو FastAPI؟',
      'يمكنني تحليل النصوص باستخدام NLP وتعلم الآلة',
    ];
    return responses[DateTime.now().second % responses.length];
  }
}

// إضافة التخزين المؤقت
import 'cache_service.dart';
import 'performance_monitor.dart';

final CacheService _cache = CacheService();
final PerformanceMonitor _monitor = PerformanceMonitor();

Future<String> generateResponseOptimized(String input) async {
  final stopwatch = Stopwatch()..start();
  
  // التحقق من التخزين المؤقت
  if (_cache.has(input)) {
    final cached = _cache.get(input);
    stopwatch.stop();
    _monitor.record('cached_response', stopwatch.elapsed);
    return '$cached\n\n⚡ (من التخزين المؤقت)';
  }
  
  final response = await generateResponse(input);
  _cache.set(input, response);
  
  stopwatch.stop();
  _monitor.record('fresh_response', stopwatch.elapsed);
  
  return response;
}

String getPerformanceStats() {
  return _monitor.getPerformanceReport();
}
