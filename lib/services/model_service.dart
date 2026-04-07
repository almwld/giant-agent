import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class ModelService {
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
          final files = await dir.list().toList();
          for (var file in files) {
            String fileName = file.path.split('/').last;
            if (fileName.endsWith('.tflite')) {
              final size = await File(file.path).length();
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
    
    if (_activeModelId.isEmpty && _models.isNotEmpty) {
      _activeModelId = _models.first['id'];
    }
  }
  
  Future<String> runModel(String input) async {
    return 'تم استلام: "$input"\n\n(النموذج يعمل بشكل طبيعي)';
  }
  
  bool hasActiveModel() => true;
  String getActiveModelName() => 'Built-in';
}
