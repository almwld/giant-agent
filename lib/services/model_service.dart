import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
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
            if (fileName.endsWith('.tflite')) {
              File modelFile = File(file.path);
              int size = await modelFile.length();
              _models.add({
                'id': fileName,
                'name': fileName,
                'size': (size / 1024 / 1024).toStringAsFixed(2),
              });
            }
          }
        } catch (e) {}
      }
    }
    
    _models.add({
      'id': 'builtin',
      'name': 'Built-in AI',
      'size': '0',
    });
    
    if (_activeModelId.isEmpty && _models.isNotEmpty) {
      _activeModelId = _models.first['id'];
    }
  }
  
  List<Map<String, dynamic>> getModels() => _models;
  
  Map<String, dynamic> getActiveModel() {
    if (_models.isEmpty) {
      return {'id': 'builtin', 'name': 'Built-in AI', 'size': '0'};
    }
    return _models.firstWhere((m) => m['id'] == _activeModelId, orElse: () => _models.first);
  }
  
  Future<bool> addModelFromFile() async {
    try {
      await Permission.storage.request();
      
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['tflite'],
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
    } else if (lower.contains('+')) {
      try {
        final parts = input.split('+');
        double a = double.parse(parts[0].trim());
        double b = double.parse(parts[1].trim());
        return '🧮 النتيجة: ${a + b}';
      } catch (e) {}
    }
    
    List<String> responses = [
      'سؤال جيد! كيف يمكنني مساعدتك؟',
      'أفهم ما تقصد. هل تريد معرفة المزيد؟',
      'هذا مثير للاهتمام! أخبرني أكثر.',
    ];
    return responses[DateTime.now().second % responses.length];
  }
}
