import 'dart:convert';
import 'package:flutter/services.dart';
import '../services/llama_service.dart';

class ModelService {
  static final ModelService _instance = ModelService._internal();
  factory ModelService() => _instance;
  ModelService._internal();
  final LlamaService _llama = LlamaService.instance;
  static const MethodChannel _agentTools = MethodChannel('giant_agent/tools');
  List<Map<String, dynamic>> _models = [];
  String _activeModelId = '';
  bool _isLoading = false;

  Future<void> init() => scanModels();
  Future<void> scanModels() async {
    final found = await _llama.discoverModels();
    _models = found.map((m) => <String, dynamic>{
      'id': m.id, 'name': m.name, 'path': m.path, 'size': m.size,
      'sizeBytes': m.sizeBytes, 'type': 'GGUF', 'isLoaded': false, 'stats': 'available',
    }).toList();
    if (!_models.any((m) => m['id'] == _activeModelId)) _activeModelId = '';
    if (_activeModelId.isEmpty && _models.isNotEmpty) await switchModel(_models.first['id'] as String);
  }
  Future<void> refreshModels() => scanModels();
  Future<bool> importModelFromFile() async {
    final model = await _llama.importModel();
    if (model == null) return false;
    await scanModels();
    return _models.any((m) => m['path'] == model.path);
  }
  Future<bool> switchModel(String modelId) async {
    Map<String, dynamic>? model;
    for (final item in _models) { if (item['id'] == modelId) { model = item; break; } }
    if (model == null || _isLoading) return false;
    _isLoading = true;
    try {
      final ok = await _llama.loadModel(model['path'] as String);
      if (ok) _activeModelId = modelId;
      return ok;
    } finally { _isLoading = false; }
  }
  bool hasActiveModel() => _activeModelId.isNotEmpty && _models.any((m) => m['id'] == _activeModelId);
  String getActiveModelName() => getActiveModel()['name']?.toString() ?? 'لا يوجد';
  String getActiveModelSize() => getActiveModel()['size']?.toString() ?? '0';
  Map<String, dynamic> getActiveModel() {
    for (final m in _models) { if (m['id'] == _activeModelId) return m; }
    return {'id': 'no_model', 'name': 'لا يوجد نموذج GGUF', 'size': '0', 'type': 'NONE'};
  }
  List<Map<String, dynamic>> getModels() => List.unmodifiable(_models);

  Future<Map<String, dynamic>> createFile({required String path, required String content}) async {
    final result = await _agentTools.invokeMapMethod<String, dynamic>('createFile', {
      'path': path,
      'content': content,
    });
    if (result == null || result['ok'] != true) {
      throw PlatformException(code: 'CREATE_FILE_FAILED', message: 'Native file tool returned no success result.');
    }
    return result;
  }

  Future<String> processInput(String input) async {
    if (!hasActiveModel()) return '⚠️ استورد نموذج GGUF واختره أولاً.';
    try {
      final prompt = '''أنت Giant Agent، مساعد محلي يعمل دون اتصال. أجب بلغة المستخدم بوضوح.
يمكنك إنشاء ملف داخل مساحة العمل فقط عند طلب المستخدم ذلك صراحةً.
عند الحاجة لإنشاء ملف، أخرج استدعاء أداة واحداً فقط بهذا التنسيق الحرفي:
<tool_call>{"name":"create_file","arguments":{"path":"notes/example.md","content":"محتوى الملف"}}</tool_call>
استخدم مساراً نسبياً وامتداداً مسموحاً، ولا تدّع إنشاء الملف قبل ظهور نتيجة التنفيذ.
إذا لم يطلب المستخدم إنشاء ملف، أجب بصورة طبيعية.
لا تعرض التفكير الداخلي التفصيلي ولا تختلق نتائج.

المستخدم: $input

المساعد:''';
      final generated = await _llama.generate(prompt, maxTokens: 512, temperature: .25);
      final match = RegExp(r'<tool_call>\s*(\{.*?\})\s*</tool_call>', dotAll: true).firstMatch(generated);
      if (match == null) return generated;
      try {
        final payload = jsonDecode(match.group(1)!) as Map<String, dynamic>;
        if (payload['name'] != 'create_file') return 'تعذر تنفيذ الأداة: اسم الأداة غير مدعوم.';
        final args = payload['arguments'] as Map<String, dynamic>;
        final result = await createFile(
          path: args['path']?.toString() ?? '',
          content: args['content']?.toString() ?? '',
        );
        return 'تم إنشاء الملف فعلياً داخل مساحة عمل التطبيق: ${result['path']}';
      } on PlatformException catch (e) {
        return 'فشل إنشاء الملف: ${e.message ?? e.code}';
      } catch (e) {
        return 'تعذر تحليل استدعاء الأداة أو تنفيذه: $e';
      }
    } catch (e) { return 'تعذر تشغيل النموذج المحلي: $e'; }
  }
}
