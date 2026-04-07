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
  
  Future<String> generateResponse(String input) async {
    String lower = input.toLowerCase();
    
    if (lower.contains('تحليل بيانات')) {
      List<num> numbers = [10, 20, 30, 40, 50];
      return await _python.createDataAnalyzer(numbers);
    }
    
    if (lower.contains('تحليل نص')) {
      String text = input.replaceAll('تحليل نص', '').trim();
      if (text.isEmpty) text = 'الذكاء الاصطناعي هو مستقبل التكنولوجيا';
      return await _python.analyzeTextWithNLP(text);
    }
    
    if (lower.contains('تعلم آلة')) {
      return await _python.createAndTrainModel();
    }
    
    if (lower.contains('أتمتة')) {
      List<String> tasks = ['تحليل بيانات', 'معالجة نصوص', 'توليد تقرير'];
      return await _python.automateTasks(tasks);
    }
    
    if (lower.contains('مرحبا')) {
      return 'مرحباً! 👋 أنا Giant Agent X\nأستطيع:\n• تحليل بيانات 📊\n• تحليل نصوص 📝\n• تعلم آلة 🧠\n• أتمتة المهام ⚡';
    }
    
    if (lower.contains('كيف حالك')) {
      return 'أنا بخير، شكراً! 🧠 جاهز لمساعدتك.';
    }
    
    if (lower.contains('شكرا')) {
      return 'العفو! 🤝 دائماً في خدمتك.';
    }
    
    if (lower.contains('+')) {
      final parts = input.split('+');
      try {
        double a = double.parse(parts[0].trim());
        double b = double.parse(parts[1].trim());
        return '🧮 النتيجة: ${a + b}';
      } catch (e) {}
    }
    
    return 'سؤال جيد! كيف يمكنني مساعدتك؟';
  }
}
