import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class ModelService {
  static final ModelService _instance = ModelService._internal();
  factory ModelService() => _instance;
  ModelService._internal();
  
  List<Map<String, dynamic>> _models = [];
  String _activeModelId = '';
  
  Future<void> init() async {
    await _scanModels();
  }
  
  Future<void> _scanModels() async {
    _models.clear();
    
    // المسارات الممكنة للنماذج
    List<String> paths = [
      '/storage/emulated/0/Download/models/',
      '/sdcard/Download/models/',
      '/storage/emulated/0/Models/',
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
    
    // نموذج افتراضي
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
      // طلب الصلاحية
      PermissionStatus status = await Permission.storage.request();
      if (!status.isGranted) {
        return false;
      }
      
      // اختيار ملف
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['tflite', 'onnx', 'gguf'],
      );
      
      if (result != null) {
        String sourcePath = result.files.single.path!;
        String fileName = result.files.single.name;
        
        // مجلد الوجهة
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
  
  List<Map<String, dynamic>> getModels() {
    return _models;
  }
  
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
  
  // ردود ذكية
  Future<String> generateResponse(String input) async {
    String lower = input.toLowerCase();
    
    if (lower.contains('مرحبا')) {
      return 'مرحباً! 👋 أنا Giant Agent X. كيف يمكنني مساعدتك؟';
    } else if (lower.contains('كيف حالك')) {
      return 'أنا بخير، شكراً! 🧠 جاهز لمساعدتك.';
    } else if (lower.contains('شكرا')) {
      return 'العفو! 🤝 دائماً في خدمتك.';
    } else if (lower.contains('وداعا')) {
      return 'وداعاً! 👋 سعدت بمساعدتك.';
    } else if (lower.contains('كود')) {
      return '```dart\nvoid main() {\n  print("Hello from Giant Agent X!");\n}\n```';
    } else if (lower.contains('موقع')) {
      return '<html><body><h1>Giant Agent X</h1></body></html>';
    } else if (lower.contains('حلل')) {
      String text = input.replaceAll('حلل', '').trim();
      return '📊 تحليل النص:\nالطول: ${text.length} حرف\nالكلمات: ${text.split(' ').length} كلمة';
    } else if (lower.contains('+') || lower.contains('-') || lower.contains('*') || lower.contains('/')) {
      return _calculate(input);
    } else {
      List<String> responses = [
        'سؤال جيد! كيف يمكنني مساعدتك؟',
        'أفهم ما تقصد. هل تريد معرفة المزيد؟',
        'هذا مثير للاهتمام! أخبرني أكثر.',
        'شكراً على سؤالك. دعني أفكر في الأمر...',
      ];
      return responses[DateTime.now().second % responses.length];
    }
  }
  
  String _calculate(String input) {
    try {
      if (input.contains('+')) {
        List<String> parts = input.split('+');
        double a = double.parse(parts[0].trim());
        double b = double.parse(parts[1].trim());
        return 'النتيجة: ${a + b}';
      } else if (input.contains('-')) {
        List<String> parts = input.split('-');
        double a = double.parse(parts[0].trim());
        double b = double.parse(parts[1].trim());
        return 'النتيجة: ${a - b}';
      } else if (input.contains('*')) {
        List<String> parts = input.split('*');
        double a = double.parse(parts[0].trim());
        double b = double.parse(parts[1].trim());
        return 'النتيجة: ${a * b}';
      } else if (input.contains('/')) {
        List<String> parts = input.split('/');
        double a = double.parse(parts[0].trim());
        double b = double.parse(parts[1].trim());
        if (b == 0) return 'لا يمكن القسمة على صفر';
        return 'النتيجة: ${a / b}';
      }
    } catch (e) {}
    return 'خطأ في العملية الحسابية';
  }
}
