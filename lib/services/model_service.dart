import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import '../services/llama_service.dart';
import '../tools/gain_terminal_tool.dart';
import '../tools/terminal_tool_coordinator.dart';
import 'agent_memory_service.dart';
import 'openrouter_service.dart';
import '../tools/tool_manager.dart';

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
  Future<bool> Function(String command)? requestTerminalApproval;
  void Function(Map<String, dynamic> event)? onAgentEvent;
  final GainTerminalTool _gainTerminal = GainTerminalTool();
  Future<void> _requestTail = Future<void>.value();

  /// One FIFO lock protects every operation that touches the mutable JNI model.
  Future<T> _withRuntimeLock<T>(Future<T> Function() operation) async {
    final gate = Completer<void>();
    final previous = _requestTail;
    _requestTail = gate.future;
    try {
      await previous;
      _isLoading = true;
      return await operation();
    } finally {
      _isLoading = false;
      if (!gate.isCompleted) gate.complete();
    }
  }

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
    final model = await _withRuntimeLock(() => _llama.importModel());
    if (model == null) return false;
    await scanModels();
    return _models.any((m) => m['path'] == model.path);
  }
  Future<bool> switchModel(String modelId) async {
    Map<String, dynamic>? model;
    for (final item in _models) { if (item['id'] == modelId) { model = item; break; } }
    if (model == null) return false;
    return _withRuntimeLock(() async {
      final ok = await _llama.loadModel(model!['path'] as String);
      if (ok) _activeModelId = modelId;
      return ok;
    });
  }

  Future<bool> loadModelByPath(String modelPath) async {
    await scanModels();
    for (final model in _models) {
      if (model['path'] == modelPath) return switchModel(model['id'] as String);
    }
    return false;
  }

  Future<bool> isModelLoaded() => _llama.isLoaded();
  bool get isBusy => _isLoading;
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
    final name = payload['name']?.toString() ?? '';
    if (!ToolManager().supports(name)) {
      throw FormatException('Unsupported tool: $name');
    }
    final args = payload['arguments'];
    if (args is! Map<String, dynamic>) {
      throw const FormatException('Tool arguments must be an object.');
    }
    switch (name) {
      case 'create_file':
        return createFile(path: args['path']?.toString() ?? '', content: args['content']?.toString() ?? '');
      case 'read_file':
        return readFile(path: args['path']?.toString() ?? '');
      case 'write_file':
        return writeFile(path: args['path']?.toString() ?? '', content: args['content']?.toString() ?? '');
      case 'execute_python':
        return executePython(code: args['code']?.toString() ?? '');
      case 'gain_terminal':
        final approval = requestTerminalApproval;
        if (approval == null) {
          return <String, dynamic>{
            'ok': false,
            'denied': true,
            'error': 'Terminal approval UI is unavailable.',
          };
        }
        final coordinator = TerminalToolCoordinator(
          requestApproval: approval,
          execute: (command, timeout) =>
              _gainTerminal.execute(command, timeout: timeout),
          onEvent: onAgentEvent,
        );
        return coordinator.execute(
          command: args['command']?.toString() ?? '',
          timeoutSeconds: args['timeout_seconds'] is int
              ? args['timeout_seconds'] as int
              : 60,
        );
      default:
        throw FormatException('Unsupported tool: $name');
    }
  }

  /// Serializes requests because llama.cpp owns one mutable native context.
  /// Concurrent calls can interleave prompts, cancellation and tool execution.
  Future<String> processInput(
    String input, {
    String conversationId = 'global',
    bool persistTurn = true,
  }) {
    return _withRuntimeLock(() async {
      final context = await AgentMemoryService.instance.buildContext(
        input,
        conversationId: conversationId,
      );
      final response = await _processInput(
        context.isEmpty ? input : '$context\n\nطلب المستخدم: $input',
      );
      if (persistTurn) {
        await AgentMemoryService.instance.saveTurn(
          input,
          response,
          conversationId: conversationId,
        );
      }
      return response;
    });
  }

  static const int _maxPromptCharacters = 9000;

  String _boundPrompt(String prompt) {
    if (prompt.length <= _maxPromptCharacters) return prompt;
    const headLength = 1800;
    const tailLength = _maxPromptCharacters - headLength;
    return '${prompt.substring(0, headLength)}\n\n[تم اختصار السياق الأقدم لتجنب تجاوز نافذة النموذج]\n\n'
        '${prompt.substring(prompt.length - tailLength)}';
  }

  Future<String> _generateText(
    String prompt, {
    required int maxTokens,
    required double temperature,
  }) async {
    if (await OpenRouterService.instance.isEnabled()) {
      return OpenRouterService.instance.generate(
        prompt,
        maxTokens: maxTokens,
        temperature: temperature,
      );
    }
    return _llama.generate(
      prompt,
      maxTokens: maxTokens,
      temperature: temperature,
    );
  }

  Future<String> _processInput(String input) async {
    _cancelRequested = false;
    input = _boundPrompt(input);
    if (!hasActiveModel() && !await OpenRouterService.instance.isEnabled()) {
      return '⚠️ اختر نموذج GGUF محلياً أو فعّل مزود OpenRouter من شريط الإدخال.';
    }
    final toolCatalog = ToolManager().promptCatalog;
    final history = StringBuffer('''أنت Giant Agent، مساعد ذكي متعدد المصادر. أجب بلغة المستخدم.
الأدوات المتاحة فعلياً:
$toolCatalog
عندما يطلب المستخدم إنشاء واجهة ويب أو نموذج تفاعلي أو تطبيق بسيط، أنشئ ملفاً واحداً باسم index.html باستخدام create_file، واجعل HTML وCSS وJavaScript مكتملة ومضمّنة داخل الملف نفسه حتى تعمل مباشرة في معاينة WebView المحلية دون اتصال. لا تعتمد على CDN أو ملفات خارجية أو خدمات شبكة. صمّم واجهة متجاوبة مع الهاتف، وأضف تفاعلات JavaScript المطلوبة. إذا طلب المستخدم مشروع Flutter أصلياً، أنشئ ملفات Dart المناسبة ولا تدّع أن WebView تستطيع تشغيلها؛ فهي تعرض الكود فقط.
عند الحاجة لاستخدام أداة أخرج استدعاءً واحداً فقط بالصيغة التالية، مع اسم أداة موجود في القائمة أعلاه ووسائط مطابقة لمثالها:
<tool_call>{"name":"tool_name","arguments":{}}</tool_call>
أو:
<tool_call>{"name":"gain_terminal","arguments":{"command":"pwd && ls","timeout_seconds":30}}</tool_call>
لا تدّع نجاح أي عملية قبل استلام نتيجة الأداة. إذا كانت النتيجة ok=false فاشرح الفشل ولا تعلن النجاح. لا تطلب أدوات إذا لم تكن لازمة.
إذا كان الطلب سؤالاً مباشراً أو شرحاً أو مراجعة/تصحيحاً بسيطاً لمقطع كود أرسله المستخدم، فأجب مباشرة في المحادثة دون إنشاء خطة أو استدعاء أدوات. لا تنشئ أو تعدّل ملفات ولا تشغّل أدوات إلا إذا طلب المستخدم ذلك صراحة أو كانت الأداة ضرورية لإنجاز المطلوب.
أداة gain_terminal تنفذ أوامر Android /system/bin/sh بصلاحيات التطبيق فقط، ولا تملك root. لا تستدعها إلا إذا كانت ضرورية وبعد أن يوافق المستخدم على نص الأمر المطابق حرفياً في نافذة التأكيد.
لا تعرض التفكير الداخلي التفصيلي.

المستخدم: $input

المساعد:''');
    try {
      final executedCalls = <String>{};
      const maxToolCalls = 16;
      for (var step = 0; step < maxToolCalls; step++) {
        if (_cancelRequested) return 'تم إيقاف تنفيذ الوكيل بناءً على طلب المستخدم.';
        final generated = await _generateText(history.toString(), maxTokens: 768, temperature: .25);
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
