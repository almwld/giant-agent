import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'model_runner.dart';

class ModelService {
  final ModelRunner _runner = ModelRunner();
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
    
    print('🔍 جاري البحث عن نماذج TFLite...');
    
    for (String path in searchPaths) {
      Directory dir = Directory(path);
      if (await dir.exists()) {
        try {
          final files = await dir.list().toList();
          for (var file in files) {
            String fileName = file.path.split('/').last;
            if (fileName.endsWith('.tflite')) {
              final size = await File(file.path).length();
              print('✅ تم العثور على نموذج: $fileName (${(size/1024/1024).toStringAsFixed(2)} MB)');
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
    
    if (_models.isEmpty) {
      print('⚠️ لم يتم العثور على نماذج TFLite');
      _models.add({
        'id': 'no_model',
        'name': '⚠️ لا يوجد نموذج',
        'path': null,
        'size': '0',
        'type': 'none',
      });
    }
    
    if (_activeModelId.isEmpty && _models.isNotEmpty && _models.first['id'] != 'no_model') {
      _activeModelId = _models.first['id'];
      await _loadModel(_models.first['path']);
    }
  }
  
  Future<void> _loadModel(String? path) async {
    if (path != null) {
      print('📥 جاري تحميل النموذج: $path');
      final loaded = await _runner.loadModel(path);
      if (loaded) {
        print('✅ النموذج جاهز للاستخدام');
      } else {
        print('❌ فشل تحميل النموذج');
      }
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
      await _loadModel(model['path']);
      return true;
    }
    return false;
  }
  
  bool hasActiveModel() {
    return _runner.isLoaded();
  }
  
  String getActiveModelName() {
    return _runner.getModelName();
  }
  
  Future<String> runModel(String input) async {
    return await _runner.run(input);
  }
  
  void dispose() {
    _runner.dispose();
  }
}
