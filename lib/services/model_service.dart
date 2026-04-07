import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class ModelService {
  static final ModelService _instance = ModelService._internal();
  factory ModelService() => _instance;
  ModelService._internal();
  
  List<Map<String, dynamic>> _models = [];
  String _activeModelId = '';
  File? _currentModelFile;
  
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
            if (fileName.endsWith('.tflite') || 
                fileName.endsWith('.onnx') || 
                fileName.endsWith('.gguf') ||
                fileName.endsWith('.bin')) {
              
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
    
    if (_models.isEmpty) {
      _models.add({
        'id': 'no_model',
        'name': 'لا يوجد نموذج',
        'path': null,
        'size': '0',
        'type': 'none',
      });
    }
    
    if (_activeModelId.isEmpty && _models.isNotEmpty && _models.first['id'] != 'no_model') {
      _activeModelId = _models.first['id'];
      _currentModelFile = File(_models.first['path']);
    }
  }
  
  Future<void> refreshModels() async {
    await _scanModels();
  }
  
  Future<bool> addModelFromFile() async {
    try {
      await Permission.storage.request();
      
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['tflite', 'onnx', 'gguf', 'bin'],
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
      return {'id': 'no_model', 'name': 'لا يوجد نموذج', 'size': '0', 'type': 'none'};
    }
    return _models.firstWhere((m) => m['id'] == _activeModelId, orElse: () => _models.first);
  }
  
  Future<bool> switchModel(String modelId) async {
    Map<String, dynamic>? model = _models.firstWhere((m) => m['id'] == modelId, orElse: () => {});
    if (model.isNotEmpty && model['path'] != null) {
      _activeModelId = modelId;
      _currentModelFile = File(model['path']);
      return true;
    }
    return false;
  }
  
  // تشغيل النموذج - هنا سيتم تمرير المدخلات إلى النموذج الفعلي
  Future<String> runModel(String input) async {
    if (_currentModelFile == null) {
      return '⚠️ يرجى تحميل نموذج أولاً';
    }
    
    // هنا يتم تمرير النص إلى النموذج الفعلي
    // حاليًا نقوم بمحاكاة بسيطة، يمكن استبدالها بـ TFLite الفعلي
    
    // محاكاة استجابة النموذج
    await Future.delayed(Duration(milliseconds: 500));
    
    // هذه مجرد محاكاة - يجب استبدالها بتشغيل النموذج الفعلي
    return '[استجابة من النموذج ${_currentModelFile!.path.split('/').last}]:\n\nتم استلام مدخلاتك: "$input"\n\nالنموذج يعمل بشكل طبيعي.';
  }
  
  bool hasActiveModel() {
    return _currentModelFile != null;
  }
}
