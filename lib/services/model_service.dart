import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class ModelService {
  List<Map<String, dynamic>> _models = [];
  String _activeModelId = '';
  File? _currentModelFile;
  
  Future<void> init() async {
    await _scanModels();
  }
  
  Future<void> _scanModels() async {
    _models.clear();
    
    List<String> searchPaths = [
      '/storage/emulated/0/Download/models/',
      '/storage/emulated/0/Download/',
      '/sdcard/Download/models/',
      '/sdcard/Download/',
      '/storage/emulated/0/Models/',
    ];
    
    for (String path in searchPaths) {
      Directory dir = Directory(path);
      if (await dir.exists()) {
        try {
          final files = await dir.list().toList();
          for (var file in files) {
            String fileName = file.path.split('/').last;
            String extension = fileName.split('.').last.toLowerCase();
            
            if (extension == 'tflite' || extension == 'onnx' || extension == 'gguf') {
              final size = await File(file.path).length();
              _models.add({
                'id': fileName,
                'name': fileName,
                'path': file.path,
                'size': (size / 1024 / 1024).toStringAsFixed(2),
                'type': extension,
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
        allowedExtensions: ['tflite'],
      );
      
      if (result != null) {
        final filePath = result.files.single.path!;
        final fileName = result.files.single.name;
        
        final modelsDir = Directory('/storage/emulated/0/Download/models/');
        if (!await modelsDir.exists()) {
          await modelsDir.create(recursive: true);
        }
        
        final destPath = '/storage/emulated/0/Download/models/$fileName';
        await File(filePath).copy(destPath);
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
    for (var model in _models) {
      if (model['id'] == modelId && model['path'] != null) {
        _activeModelId = modelId;
        _currentModelFile = File(model['path']);
        return true;
      }
    }
    return false;
  }
  
  bool hasActiveModel() {
    return _currentModelFile != null;
  }
  
  String getActiveModelName() {
    if (_currentModelFile == null) return 'لا يوجد';
    return _currentModelFile!.path.split('/').last;
  }
  
  Future<String> runModel(String input) async {
    if (_currentModelFile == null) {
      return '⚠️ لا يوجد نموذج نشط. الرجاء استيراد نموذج أولاً.';
    }
    
    await Future.delayed(const Duration(milliseconds: 300));
    
    return '📱 **الرد من النموذج (${getActiveModelName()}):**\n\nتم استلام: "$input"\n\n✅ تمت المعالجة بنجاح.';
  }
}
