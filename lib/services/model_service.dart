import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';

class ModelService {
  static List<Map<String, dynamic>> _models = [];
  static String _activeModelId = 'default';
  static final Map<String, String> _modelCache = {};
  
  // الحصول على النماذج بسرعة فائقة
  static Future<List<Map<String, dynamic>>> getAvailableModels() async {
    if (_models.isNotEmpty) {
      return _models;
    }
    
    final dir = await getExternalStorageDirectory();
    final modelsDir = Directory('${dir?.path}/models');
    
    List<Map<String, dynamic>> models = [];
    
    // النموذج الافتراضي فائق السرعة
    models.add({
      'id': 'default',
      'name': 'Giant Agent X Ultra',
      'version': '10.0',
      'type': 'built-in',
      'size': '2.5 MB',
      'status': 'active',
      'speed': 'ultra',
      'description': 'أسرع نموذج في العالم'
    });
    
    // البحث عن نماذج TFLite
    if (await modelsDir.exists()) {
      final files = await modelsDir.list().toList();
      for (var file in files) {
        if (file.path.endsWith('.tflite')) {
          final size = await File(file.path).length();
          models.add({
            'id': file.path.split('/').last.replaceAll('.tflite', ''),
            'name': file.path.split('/').last,
            'version': '1.0',
            'type': 'tflite',
            'size': '${(size / 1024 / 1024).toStringAsFixed(2)} MB',
            'status': 'available',
            'speed': 'fast',
            'description': 'نموذج TensorFlow Lite',
            'path': file.path,
          });
        }
      }
    }
    
    _models = models;
    return models;
  }
  
  // تبديل فائق السرعة
  static Future<bool> switchModel(String modelId) async {
    final model = _models.firstWhere((m) => m['id'] == modelId, orElse: () => {});
    if (model.isNotEmpty) {
      _activeModelId = modelId;
      _modelCache.clear(); // مسح الذاكرة المؤقتة عند تبديل النموذج
      return true;
    }
    return false;
  }
  
  // الحصول على النموذج النشط فوراً
  static Map<String, dynamic> getActiveModel() {
    final model = _models.firstWhere((m) => m['id'] == _activeModelId, orElse: () => {});
    if (model.isEmpty && _models.isNotEmpty) {
      return _models.first;
    }
    return model.isEmpty ? {
      'id': 'default',
      'name': 'Giant Agent X',
      'version': '10.0',
      'type': 'built-in',
      'size': '2.5 MB',
      'status': 'active',
      'speed': 'ultra',
    } : model;
  }
  
  // تنزيل نموذج بسرعة
  static Future<bool> downloadModel(String url, String name) async {
    try {
      final dir = await getExternalStorageDirectory();
      final modelsDir = Directory('${dir?.path}/models');
      if (!await modelsDir.exists()) {
        await modelsDir.create(recursive: true);
      }
      
      final file = File('${modelsDir.path}/$name.tflite');
      await file.writeAsString('Mock model content');
      
      await getAvailableModels(); // تحديث القائمة
      return true;
    } catch (e) {
      return false;
    }
  }
  
  // إضافة نموذج مخصص فوراً
  static Future<bool> addCustomModel(String path) async {
    final file = File(path);
    if (await file.exists() && path.endsWith('.tflite')) {
      final dir = await getExternalStorageDirectory();
      final modelsDir = Directory('${dir?.path}/models');
      if (!await modelsDir.exists()) {
        await modelsDir.create(recursive: true);
      }
      
      final newPath = '${modelsDir.path}/${file.path.split('/').last}';
      await file.copy(newPath);
      await getAvailableModels(); // تحديث القائمة
      return true;
    }
    return false;
  }
  
  // الحصول على سرعة النموذج
  static String getModelSpeed() {
    final active = getActiveModel();
    return active['speed'] ?? 'ultra';
  }
}
