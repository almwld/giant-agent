import 'dart:io';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

class ModelService {
  static final ModelService _instance = ModelService._internal();
  factory ModelService() => _instance;
  ModelService._internal();
  
  List<Map<String, dynamic>> _models = [];
  String _activeModelId = '';
  File? _currentModelFile;
  bool _isLoading = false;
  
  // مسارات البحث عن النماذج
  final List<String> _searchPaths = [
    '/storage/emulated/0/Download/models/',
    '/storage/emulated/0/Download/',
    '/sdcard/Download/models/',
    '/sdcard/Download/',
    '/storage/emulated/0/Models/',
    '/storage/emulated/0/Phi3Model/',
  ];
  
  Future<void> init() async {
    await _requestPermissions();
    await scanModels();
  }
  
  Future<void> _requestPermissions() async {
    await Permission.storage.request();
  }
  
  Future<void> scanModels() async {
    _models.clear();
    
    for (String path in _searchPaths) {
      Directory dir = Directory(path);
      if (await dir.exists()) {
        try {
          final files = await dir.list().toList();
          for (var file in files) {
            String fileName = file.path.split('/').last;
            String extension = fileName.split('.').last.toLowerCase();
            
            if (_isModelFile(extension)) {
              final size = await File(file.path).length();
              _models.add({
                'id': fileName,
                'name': fileName,
                'path': file.path,
                'size': (size / 1024 / 1024).toStringAsFixed(2),
                'type': extension.toUpperCase(),
                'isLoaded': false,
              });
            }
          }
        } catch (e) {}
      }
    }
    
    if (_models.isEmpty) {
      _models.add({
        'id': 'no_model',
        'name': '⚠️ لا يوجد نموذج',
        'path': null,
        'size': '0',
        'type': 'NONE',
        'isLoaded': false,
      });
    }
    
    // تفعيل أول نموذج موجود
    if (_activeModelId.isEmpty && _models.isNotEmpty && _models.first['id'] != 'no_model') {
      await switchModel(_models.first['id']);
    }
  }
  
  bool _isModelFile(String extension) {
    return extension == 'tflite' || 
           extension == 'onnx' || 
           extension == 'gguf' ||
           extension == 'bin' ||
           extension == 'pb';
  }
  
  Future<void> refreshModels() async {
    await scanModels();
  }
  
  Future<bool> importModelFromFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['tflite', 'onnx', 'gguf', 'bin', 'pb'],
      );
      
      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        final fileName = result.files.single.name;
        
        final modelsDir = Directory('/storage/emulated/0/Download/models/');
        if (!await modelsDir.exists()) {
          await modelsDir.create(recursive: true);
        }
        
        final destPath = '/storage/emulated/0/Download/models/$fileName';
        await File(filePath).copy(destPath);
        await scanModels();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
  
  Future<bool> switchModel(String modelId) async {
    final model = _models.firstWhere(
      (m) => m['id'] == modelId && m['path'] != null,
      orElse: () => {},
    );
    
    if (model.isNotEmpty) {
      _activeModelId = modelId;
      _currentModelFile = File(model['path']);
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
  
  String getActiveModelSize() {
    final model = getActiveModel();
    return model['size'] ?? '0';
  }
  
  Map<String, dynamic> getActiveModel() {
    if (_models.isEmpty) {
      return {'id': 'no_model', 'name': 'لا يوجد نموذج', 'size': '0', 'type': 'NONE'};
    }
    return _models.firstWhere(
      (m) => m['id'] == _activeModelId,
      orElse: () => _models.first,
    );
  }
  
  List<Map<String, dynamic>> getModels() => _models;
  
  Future<String> processInput(String input) async {
    if (!hasActiveModel()) {
      return '⚠️ **لا يوجد نموذج نشط**\n\nالرجاء اتباع الخطوات التالية:\n1. اضغط على القائمة الجانبية ☰\n2. اختر "استيراد نموذج"\n3. اختر ملف النموذج (.tflite)\n4. انتظر حتى يتم التحميل\n5. ابدأ المحادثة';
    }
    
    try {
      // محاكاة تشغيل النموذج (للتطوير الفعلي، سيتم دمج TFLite)
      await Future.delayed(Duration(milliseconds: 300));
      
      return '''
✅ **تمت المعالجة بنجاح**

📱 **النموذج:** ${getActiveModelName()}
📊 **الحجم:** ${getActiveModelSize()} MB
💬 **مدخلاتك:** "$input"

✨ **الرد من النموذج:** تم استلام طلبك وسيتم معالجته.

💡 **نصيحة:** يمكنك تحميل نماذج أقوى من HuggingFace
''';
    } catch (e) {
      return '❌ **خطأ في تشغيل النموذج**\n\n$e\n\nيرجى المحاولة مرة أخرى أو اختيار نموذج آخر.';
    }
  }
}
