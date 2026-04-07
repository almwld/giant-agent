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
    
    // جميع المسارات الممكنة للنماذج
    List<String> searchPaths = [
      '/storage/emulated/0/Download/models/',
      '/storage/emulated/0/Download/',
      '/sdcard/Download/models/',
      '/sdcard/Download/',
      '/storage/emulated/0/Phi3Model/',
      '/storage/emulated/0/Android/data/com.example.giant_agent/files/models/',
      '/data/data/com.termux/files/home/storage/downloads/models/',
    ];
    
    print('🔍 جاري البحث عن النماذج...');
    
    for (String path in searchPaths) {
      Directory dir = Directory(path);
      if (await dir.exists()) {
        print('📁 البحث في: $path');
        try {
          List<FileSystemEntity> files = await dir.list().toList();
          for (var file in files) {
            String fileName = file.path.split('/').last;
            if (fileName.endsWith('.tflite') || 
                fileName.endsWith('.onnx') || 
                fileName.endsWith('.gguf') ||
                fileName.contains('phi3')) {
              
              File modelFile = File(file.path);
              int size = await modelFile.length();
              print('✅ تم العثور على نموذج: $fileName (${(size/1024/1024).toStringAsFixed(2)} MB)');
              
              _models.add({
                'id': fileName,
                'name': fileName,
                'path': file.path,
                'size': (size / 1024 / 1024).toStringAsFixed(2),
                'type': fileName.split('.').last,
              });
            }
          }
        } catch (e) {
          print('⚠️ خطأ في قراءة $path: $e');
        }
      } else {
        print('❌ المسار غير موجود: $path');
      }
    }
    
    if (_models.isEmpty) {
      print('⚠️ لم يتم العثور على أي نماذج!');
      _models.add({
        'id': 'no_model',
        'name': '⚠️ لا يوجد نموذج - ضع ملف .tflite في مجلد Download/models',
        'path': null,
        'size': '0',
        'type': 'none',
      });
    } else {
      print('🎉 تم العثور على ${_models.length} نموذج');
    }
    
    if (_activeModelId.isEmpty && _models.isNotEmpty && _models.first['id'] != 'no_model') {
      _activeModelId = _models.first['id'];
      _currentModelFile = File(_models.first['path']);
      print('✅ تم اختيار النموذج: ${_models.first['name']}');
    }
  }
  
  Future<void> refreshModels() async {
    print('🔄 تحديث النماذج...');
    await _scanModels();
  }
  
  Future<bool> addModelFromFile() async {
    try {
      await Permission.storage.request();
      
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['tflite', 'onnx', 'gguf'],
      );
      
      if (result != null) {
        String sourcePath = result.files.single.path!;
        String fileName = result.files.single.name;
        
        // التأكد من وجود مجلد النماذج
        Directory modelsDir = Directory('/storage/emulated/0/Download/models/');
        if (!await modelsDir.exists()) {
          await modelsDir.create(recursive: true);
        }
        
        String destPath = '/storage/emulated/0/Download/models/$fileName';
        await File(sourcePath).copy(destPath);
        print('✅ تم نسخ النموذج إلى: $destPath');
        await _scanModels();
        return true;
      }
      return false;
    } catch (e) {
      print('❌ خطأ في إضافة النموذج: $e');
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
      print('✅ تم التبديل إلى النموذج: ${model['name']}');
      return true;
    }
    return false;
  }
  
  bool hasActiveModel() {
    return _currentModelFile != null && _currentModelFile!.existsSync();
  }
  
  String getActiveModelName() {
    if (_currentModelFile == null) return 'لا يوجد';
    return _currentModelFile!.path.split('/').last;
  }
  
  Future<String> runModel(String input) async {
    if (_currentModelFile == null) {
      return '⚠️ لا يوجد نموذج نشط. الرجاء اختيار نموذج من القائمة الجانبية.';
    }
    
    if (!await _currentModelFile!.exists()) {
      return '⚠️ ملف النموذج غير موجود: ${_currentModelFile!.path}\nالرجاء إعادة تحميل النموذج.';
    }
    
    // محاكاة تشغيل النموذج
    await Future.delayed(const Duration(milliseconds: 500));
    
    return '📱 **الرد من النموذج ${getActiveModelName()}:**\n\nتم استلام: "$input"\n\n✅ تمت المعالجة بنجاح.';
  }
}
