import 'dart:io';
import 'dart:isolate';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'performance_service.dart';

class ModelService {
  static final ModelService _instance = ModelService._internal();
  factory ModelService() => _instance;
  ModelService._internal();
  
  List<Map<String, dynamic>> _models = [];
  String _activeModelId = '';
  File? _currentModelFile;
  final PerformanceService _performance = PerformanceService();
  
  // معالجة غير متزامنة باستخدام Isolate
  Future<String> runModelAsync(String input) async {
    final startTime = DateTime.now();
    
    // التحقق من التخزين المؤقت أولاً
    final cached = _performance.getCachedResponse(input);
    if (cached != null) {
      _performance.recordResponseTime(DateTime.now().difference(startTime).inMilliseconds);
      return cached;
    }
    
    if (_currentModelFile == null) {
      return '⚠️ يرجى تحميل نموذج أولاً';
    }
    
    // تنفيذ النموذج في Isolate منفصل
    final response = await _performance.queueTask(() async {
      return await _executeInIsolate(input);
    });
    
    // حفظ في التخزين المؤقت
    _performance.cacheResponse(input, response);
    
    final endTime = DateTime.now();
    _performance.recordResponseTime(endTime.difference(startTime).inMilliseconds);
    
    return response;
  }
  
  Future<String> _executeInIsolate(String input) async {
    // إنشاء ReceivePort للتواصل مع الـ Isolate
    final receivePort = ReceivePort();
    
    // تشغيل الـ Isolate
    await Isolate.spawn(_isolateEntry, [receivePort.sendPort, input]);
    
    // انتظار النتيجة
    final result = await receivePort.first;
    receivePort.close();
    
    return result as String;
  }
  
  static void _isolateEntry(List<dynamic> args) {
    final sendPort = args[0] as SendPort;
    final input = args[1] as String;
    
    // محاكاة معالجة النموذج (سيتم استبدالها بتشغيل TFLite الفعلي)
    final result = _processInIsolate(input);
    
    sendPort.send(result);
  }
  
  static String _processInIsolate(String input) {
    // هنا سيتم تشغيل النموذج الفعلي
    // حالياً محاكاة بسيطة
    return '[استجابة سريعة من النموذج]:\n\nتم معالجة: "$input"';
  }
  
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
          List<FileSystemEntity> files = await dir.list().toList();
          for (var file in files) {
            String fileName = file.path.split('/').last;
            if (fileName.endsWith('.tflite') || 
                fileName.endsWith('.onnx') || 
                fileName.endsWith('.gguf')) {
              
              File modelFile = File(file.path);
              int size = await modelFile.length();
              _models.add({
                'id': fileName,
                'name': fileName,
                'path': file.path,
                'size': (size / 1024 / 1024).toStringAsFixed(2),
                'type': fileName.split('.').last,
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
        allowedExtensions: ['tflite', 'onnx', 'gguf'],
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
      _currentModelFile = File(model['path']);
      _performance.clearCache(); // مسح التخزين المؤقت عند تبديل النموذج
      return true;
    }
    return false;
  }
  
  bool hasActiveModel() {
    return _currentModelFile != null;
  }
  
  Map<String, dynamic> getPerformanceStats() {
    return _performance.getPerformanceStats();
  }
  
  Future<String> runModel(String input) async {
    return await runModelAsync(input);
  }
}

import '../tools/tool_manager.dart';
import 'long_term_memory.dart';
import 'planner_service.dart';

final ToolManager _toolManager = ToolManager();
final LongTermMemory _memory = LongTermMemory();
final PlannerService _planner = PlannerService();

// تهيئة الأدوات
void _initTools() {
  _toolManager.registerTools();
}

// معالجة ذكية مع دعم الأدوات والتخطيط
Future<String> processWithTools(String input) async {
  _initTools();
  await _memory.init();
  
  final lower = input.toLowerCase();
  
  // التحقق من وجود أمر أداة
  if (lower.contains('احسب') || lower.contains('calculate')) {
    final expression = input.replaceAll(RegExp(r'احسب|calculate'), '').trim();
    return await _toolManager.executeTool('calculator', {'expression': expression});
  }
  
  if (lower.contains('اكتب ملف') || lower.contains('save file')) {
    final parts = input.split('محتوى');
    final filename = parts[0].replaceAll('اكتب ملف', '').trim();
    final content = parts.length > 1 ? parts[1].trim() : 'محتوى افتراضي';
    return await _toolManager.executeTool('file_writer', {'filename': filename, 'content': content});
  }
  
  if (lower.contains('اقرأ ملف') || lower.contains('read file')) {
    final filename = input.replaceAll(RegExp(r'اقرأ ملف|read file'), '').trim();
    return await _toolManager.executeTool('file_reader', {'filename': filename});
  }
  
  if (lower.contains('تذكر') || lower.contains('remember')) {
    final parts = input.replaceAll('تذكر', '').trim().split(':');
    if (parts.length == 2) {
      await _memory.saveMemory(parts[0].trim(), parts[1].trim());
      return '✅ تم حفظ: ${parts[0]} = ${parts[1]}';
    }
    return 'استخدم: تذكر المفتاح: القيمة';
  }
  
  if (lower.contains('استرجع') || lower.contains('recall')) {
    final key = input.replaceAll(RegExp(r'استرجع|recall'), '').trim();
    final value = await _memory.recallMemory(key);
    return value != null ? '📝 $key: $value' : 'لا توجد معلومات عن $key';
  }
  
  if (lower.contains('خطة') || lower.contains('plan')) {
    final goal = input.replaceAll(RegExp(r'خطة|plan'), '').trim();
    final plan = await _planner.createPlan(goal);
    String result = '📋 **الخطة الموضوعة:**\n\n';
    for (var step in plan) {
      result += '${step['step']}. ${step['action']}\n';
    }
    result += '\n${_planner.getProgress()}';
    return result;
  }
  
  if (lower.contains('نفذ') || lower.contains('execute')) {
    final action = _planner.getNextAction();
    if (action == 'completed') {
      return '✅ تم إكمال جميع الخطوات!';
    }
    return '🔄 جاري تنفيذ: $action\n${_planner.getProgress()}';
  }
  
  if (lower.contains('مهام معلقة') || lower.contains('pending tasks')) {
    final tasks = await _memory.getPendingTasks();
    if (tasks.isEmpty) return 'لا توجد مهام معلقة';
    String result = '📋 **المهام المعلقة:**\n';
    for (var task in tasks) {
      result += '• ${task['task']}\n';
    }
    return result;
  }
  
  // استدعاء النموذج الأساسي
  return await runModel(input);
}
