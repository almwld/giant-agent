import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'real_model_runner.dart';

class ModelService {
  final RealModelRunner _runner = RealModelRunner();
  List<Map<String, dynamic>> _models = [];
  String _activeModelId = '';
  
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
    ];
    
    for (String path in searchPaths) {
      Directory dir = Directory(path);
      if (await dir.exists()) {
        try {
          final files = await dir.list().toList();
          for (var file in files) {
            String fileName = file.path.split('/').last;
            if (fileName.endsWith('.tflite')) {
              final size = await File(file.path).length();
              _models.add({
                'id': fileName,
                'name': fileName,
                'path': file.path,
                'size': (size / 1024 / 1024).toStringAsFixed(2),
                'type': 'tflite',
              });
            }
          }
        } catch (e) {}
      }
    }
    
    if (_activeModelId.isEmpty && _models.isNotEmpty) {
      _activeModelId = _models.first['id'];
      await _runner.loadModel(_models.first['path']);
    }
  }
  
  Future<void> refreshModels() async {
    await _scanModels();
  }
  
  Future<bool> addModelFromFile() async {
    try {
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
    final model = _models.firstWhere((m) => m['id'] == modelId, orElse: () => null);
    if (model != null && model['path'] != null) {
      _activeModelId = modelId;
      return await _runner.loadModel(model['path']);
    }
    return false;
  }
  
  bool hasActiveModel() => _runner.isLoaded();
  bool isLoading() => _runner.isLoading();
  
  String getActiveModelName() => _runner.getModelName();
  
  Future<String> runModel(String input) async {
    return await _runner.run(input);
  }
  
  void dispose() {
    _runner.dispose();
  }
}
