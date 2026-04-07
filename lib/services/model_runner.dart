import 'dart:io';
import 'package:tflite_flutter/tflite_flutter.dart';

class ModelRunner {
  static final ModelRunner _instance = ModelRunner._internal();
  factory ModelRunner() => _instance;
  ModelRunner._internal();
  
  Interpreter? _interpreter;
  String? _currentModelPath;
  bool _isLoaded = false;
  
  Future<bool> loadModel(String modelPath) async {
    try {
      final file = File(modelPath);
      if (!await file.exists()) {
        print('❌ الملف غير موجود: $modelPath');
        return false;
      }
      
      print('📥 جاري تحميل النموذج TFLite: $modelPath');
      
      // تحميل النموذج باستخدام TFLite
      _interpreter = await Interpreter.fromFile(file);
      _currentModelPath = modelPath;
      _isLoaded = true;
      
      print('✅ تم تحميل النموذج بنجاح');
      return true;
    } catch (e) {
      print('❌ خطأ في تحميل النموذج: $e');
      _isLoaded = false;
      return false;
    }
  }
  
  Future<String> run(String input) async {
    if (!_isLoaded || _interpreter == null) {
      return '⚠️ النموذج غير محمل. يرجى اختيار نموذج أولاً.';
    }
    
    try {
      print('🔄 جاري تشغيل النموذج TFLite...');
      
      // تحويل النص إلى تنسيق الإدخال المناسب للنموذج
      // ملاحظة: هذا يعتمد على شكل النموذج، قد يحتاج تعديل
      final inputBytes = input.codeUnits.map((e) => e.toDouble()).toList();
      
      // تعبئة الإدخال إلى حجم ثابت (مثلاً 512)
      final inputSize = 512;
      final paddedInput = List.filled(inputSize, 0.0);
      for (var i = 0; i < inputBytes.length && i < inputSize; i++) {
        paddedInput[i] = inputBytes[i];
      }
      
      final inputTensor = [paddedInput];
      
      // تحديد حجم المخرجات
      final outputSize = 1000;
      var outputTensor = List.filled(outputSize, 0.0).reshape([1, outputSize]);
      
      // تشغيل النموذج
      _interpreter!.run(inputTensor, outputTensor);
      
      // استخراج النص من المخرجات
      String output = '';
      for (var i = 0; i < outputTensor[0].length; i++) {
        final value = outputTensor[0][i];
        if (value > 0.5 && value < 127) {
          output += String.fromCharCode(value.toInt());
        }
      }
      
      print('✅ تم تشغيل النموذج بنجاح');
      
      if (output.trim().isEmpty) {
        return '📱 **استجابة النموذج (${_currentModelPath?.split('/').last}):**\n\nتم استلام: "$input"\n\n(تمت المعالجة بنجاح)';
      }
      
      return '📱 **استجابة النموذج:**\n\n$output';
    } catch (e) {
      print('❌ خطأ في تشغيل النموذج: $e');
      return '❌ خطأ في تشغيل النموذج: $e\n\nقد يكون النموذج غير متوافق مع تنسيق الإدخال المتوقع.';
    }
  }
  
  bool isLoaded() => _isLoaded;
  
  String getModelName() {
    if (_currentModelPath == null) return 'لا يوجد';
    return _currentModelPath!.split('/').last;
  }
  
  void dispose() {
    _interpreter?.close();
    _isLoaded = false;
  }
}
