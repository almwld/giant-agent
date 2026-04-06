import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

class ModelService {
  static List<Map<String, dynamic>> _models = [];
  static String _activeModel = 'default';
  
  // قائمة النماذج المتاحة
  static Future<List<Map<String, dynamic>>> getAvailableModels() async {
    final dir = await getExternalStorageDirectory();
    final modelsDir = Directory('${dir?.path}/models');
    
    List<Map<String, dynamic>> models = [];
    
    // النموذج الافتراضي
    models.add({
      'id': 'default',
      'name': 'Giant Agent X',
      'version': '10.0',
      'type': 'built-in',
      'size': '2.5 MB',
      'status': 'active',
      'description': 'النموذج الأساسي للوكيل العملاق'
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
            'description': 'نموذج TensorFlow Lite',
            'path': file.path,
          });
        }
      }
    }
    
    _models = models;
    return models;
  }
  
  // تبديل النموذج النشط
  static Future<bool> switchModel(String modelId) async {
    final model = _models.firstWhere((m) => m['id'] == modelId, orElse: () => {});
    if (model.isNotEmpty) {
      _activeModel = modelId;
      return true;
    }
    return false;
  }
  
  // الحصول على النموذج النشط
  static Map<String, dynamic> getActiveModel() {
    return _models.firstWhere((m) => m['id'] == _activeModel, orElse: () => _models.first);
  }
  
  // تنزيل نموذج جديد
  static Future<bool> downloadModel(String url, String name) async {
    try {
      final dir = await getExternalStorageDirectory();
      final modelsDir = Directory('${dir?.path}/models');
      if (!await modelsDir.exists()) {
        await modelsDir.create(recursive: true);
      }
      
      // محاكاة تنزيل (يمكن توصيلها بـ HTTP)
      final file = File('${modelsDir.path}/$name.tflite');
      await file.writeAsString('Mock model content');
      
      return true;
    } catch (e) {
      return false;
    }
  }
  
  // إضافة نموذج مخصص
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
}
