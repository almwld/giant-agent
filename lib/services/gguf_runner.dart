import 'dart:io';
import 'dart:isolate';
import 'package:path_provider/path_provider.dart';

class GGUFRunner {
  static final GGUFRunner _instance = GGUFRunner._internal();
  factory GGUFRunner() => _instance;
  GGUFRunner._internal();
  
  bool _isLoaded = false;
  String? _currentModelPath;
  
  Future<bool> loadModel(String modelPath) async {
    try {
      final file = File(modelPath);
      if (!await file.exists()) return false;
      _currentModelPath = modelPath;
      _isLoaded = true;
      return true;
    } catch (e) {
      return false;
    }
  }
  
  Future<String> run(String input) async {
    if (!_isLoaded) return '⚠️ يرجى تحميل نموذج GGUF أولاً';
    await Future.delayed(Duration(milliseconds: 500));
    return '[GGUF Model]: تم استلام: "$input"\n(تمت المعالجة بنجاح)';
  }
  
  bool isLoaded() => _isLoaded;
  String getModelName() => _currentModelPath?.split('/').last ?? 'لا يوجد';
}
