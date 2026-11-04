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
  bool _cancelRequested = false;

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

  Future<List<String>> listWorkspaceFiles() async {
    final result = await _agentTools.invokeMapMethod<String, dynamic>('listWorkspaceFiles');
    if (result == null || result['ok'] != true) {
      throw PlatformException(code: 'WORKSPACE_LIST_FAILED', message: 'Unable to list workspace files.');
    }
    return (result['files'] as List<dynamic>? ?? const []).map((item) => item.toString()).toList();
  }

  Future<Map<String, dynamic>> writeFile({required String path, required String content}) async {
    final result = await _agentTools.invokeMapMethod<String, dynamic>('writeFile', {
      'path': path,
      'content': content,
    });
    if (result == null || result['ok'] != true) {
      throw PlatformException(code: 'WRITE_FILE_FAILED', message: 'Unable to update workspace file.');
    }
    return result;
  }

  Future<Map<String, dynamic>> readFile({required String path}) async {
    final result = await _agentTools.invokeMapMethod<String, dynamic>('readFile', {'path': path});
    if (result == null || result['ok'] != true) {
      throw PlatformException(code: 'READ_FILE_FAILED', message: 'Native file tool returned no read result.');
    }
    return result;
  }

  Future<bool> cancelGeneration() async {
    _cancelRequested = true;
    return _llama.cancel();
  }

  Future<Map<String, dynamic>> exportWorkspace() async {
    final result = await _agentTools.invokeMapMethod<String, dynamic>('exportWorkspace');
    if (result == null || result['ok'] != true || result['path'] == null) {
      throw PlatformException(
        code: 'WORKSPACE_EXPORT_FAILED',
        message: result?['error']?.toString() ?? 'Workspace export failed.',
      );
    }
    return result;
  }

  Future<Map<String, dynamic>> executePython({required String code}) async {
    final result = await _agentTools.invokeMapMethod<String, dynamic>('executePython', {'code': code});
    if (result == null) {
      throw PlatformException(code: 'PYTHON_FAILED', message: 'Python runtime returned no result.');
    }
    return result;
  }

  Future<Map<String, dynamic>> _executeTool(Map<String, dynamic> payload) async {
    final name = payload['name'];
    final args = payload['arguments'];
    if (args is! Map<String, dynamic>) throw const FormatException('Tool arguments must be an object.');
    switch (name) {
      case 'create_file':
        return createFile(path: args['path']?.toString() ?? '', content: args['content']?.toString() ?? '');
      case 'read_file':
        return readFile(path: args['path']?.toString() ?? '');
      case 'write_file':
        return writeFile(path: args['path']?.toString() ?? '', content: args['content']?.toString() ?? '');
      case 'execute_python':
        return executePython(code: args['code']?.toString() ?? '');
      default:
        throw FormatException('Unsupported tool: $name');
    }
  }

  Future<String> processInput(String input) async {
    _cancelRequested = false;
    if (!hasActiveModel()) return '⚠️ استورد نموذج GGUF واختره أولاً.';
    final history = StringBuffer('''أنت Giant Agent، مساعد محلي يعمل دون اتصال. أجب بلغة المستخدم.
أدواتك:
1) create_file: arguments path و content. تنشئ ملفاً جديداً فقط ولا تستبدل الموجود.
2) read_file: arguments path. تقرأ ملفاً موجوداً داخل مساحة العمل.
3) write_file: arguments path و content. تحدّث ملفاً موجوداً داخل مساحة العمل مع الحفاظ على حدود المسارات والحجم.
4) execute_python: arguments code. يشغّل سكربت Python محلياً ضمن مفسر مقيّد؛ يدعم الحسابات والطباعة والحلقات المحدودة. لا يدعم الاستيراد أو الوصول إلى النظام أو السمات أو فتح الملفات. تعامل مع الملفات عبر أداتي create_file و read_file فقط؛ لا يملك Python صلاحية فتح الملفات.
عندما يطلب المستخدم إنشاء واجهة ويب أو نموذج تفاعلي أو تطبيق بسيط، أنشئ ملفاً واحداً باسم index.html باستخدام create_file، واجعل HTML وCSS وJavaScript مكتملة ومضمّنة داخل الملف نفسه حتى تعمل مباشرة في معاينة WebView المحلية دون اتصال. لا تعتمد على CDN أو ملفات خارجية أو خدمات شبكة. صمّم واجهة متجاوبة مع الهاتف، وأضف تفاعلات JavaScript المطلوبة. إذا طلب المستخدم مشروع Flutter أصلياً، أنشئ ملفات Dart المناسبة ولا تدّع أن WebView تستطيع تشغيلها؛ فهي تعرض الكود فقط.
عند الحاجة لاستخدام أداة أخرج استدعاءً واحداً فقط:
<tool_call>{"name":"create_file","arguments":{"path":"src/main.dart","content":"..."}}</tool_call>
أو:
<tool_call>{"name":"read_file","arguments":{"path":"index.html"}}</tool_call>
أو:
<tool_call>{"name":"write_file","arguments":{"path":"index.html","content":"<!doctype html>..."}}</tool_call>
أو:
<tool_call>{"name":"execute_python","arguments":{"code":"for i in range(1, 11):\n    print(i)"}}</tool_call>
لا تدّع نجاح أي عملية قبل استلام نتيجتها. لا تطلب أدوات إذا لم تكن لازمة.
لا تعرض التفكير الداخلي التفصيلي.

المستخدم: $input

المساعد:''');
    try {
      final executedCalls = <String>{};
      const maxToolCalls = 10;
      for (var step = 0; step < maxToolCalls; step++) {
        if (_cancelRequested) return 'تم إيقاف تنفيذ الوكيل بناءً على طلب المستخدم.';
        final generated = await _llama.generate(history.toString(), maxTokens: 768, temperature: .25);
        if (_cancelRequested) return generated.trim().isEmpty ? 'تم إيقاف التوليد.' : '${generated.trim()}\n\n[تم إيقاف التوليد]';
        final match = RegExp(r'<tool_call>\s*(\{.*?\})\s*</tool_call>', dotAll: true).firstMatch(generated);
        if (match == null) return generated.trim();
        try {
          final payload = jsonDecode(match.group(1)!) as Map<String, dynamic>;
          final signature = jsonEncode(payload);
          if (!executedCalls.add(signature)) {
            return 'أوقف الوكيل تكرار استدعاء الأداة نفسه دون تقدم. راجع النتيجة السابقة وحدد خطوة مختلفة.';
          }
          final result = await _executeTool(payload);
          if (_cancelRequested) return 'تم إيقاف الوكيل بعد اكتمال الأداة الحالية.';
          final toolName = payload['name'];
          final resultJson = jsonEncode(result);
          final pythonTail = (result['output']?.toString() ?? result['error']?.toString() ?? '');
          final boundedPythonTail = pythonTail.length > 500
              ? '${pythonTail.substring(pythonTail.length - 500)}\n[Python output truncated to last 500 characters]'
              : pythonTail;
          final pythonOk = result['ok'] == true;
          final contextResult = toolName == 'execute_python'
              ? 'ok=$pythonOk\n$boundedPythonTail'
              : resultJson;
          history
            ..write('\n\nSystem Note: $toolName execution result: ')
            ..write(contextResult)
            ..write('\nDo not claim success if the tool result contains ok=false. Continue the request; use another tool if required, otherwise provide the final answer.\n\nAssistant:');
        } on PlatformException catch (e) {
          history
            ..write('\n\nSystem Note: Tool failed: ${e.code}: ${e.message}. Do not claim success. You may correct the arguments and retry once.\n\nAssistant:');
        } catch (e) {
          return 'تعذر تحليل استدعاء الأداة أو تنفيذه: $e';
        }
      }
      return 'وصل الوكيل إلى الحد الآمن ($maxToolCalls استدعاءات أدوات) دون إنهاء المهمة. أعد الطلب لمتابعة العمل من سياق المحادثة.';
    } catch (e) {
      return 'تعذر تشغيل النموذج المحلي: $e';
    }
  }
}
