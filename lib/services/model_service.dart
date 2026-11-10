import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import '../services/llama_service.dart';
import '../agent/architecture/agent_event_bus.dart';
import 'agent_memory_service.dart';
import 'openai_compatible_provider.dart';
import 'gemini_provider.dart';
import 'model_provider_settings.dart';
import '../tools/tool_manager.dart';
import '../domain/harness/evaluator_service.dart';
import '../domain/harness/reflexion_service.dart';

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
  Future<void> _requestTail = Future<void>.value();
  String _activeRequestId = '';
  int _toolEventSequence = 0;
  late final EvaluatorService _evaluator = EvaluatorService(readWorkspaceFile: readFile);
  late final ReflexionService _reflexion = ReflexionService(
    generate: (prompt) => _generateText(
      _boundPrompt(prompt),
      maxTokens: 512,
      temperature: .1,
    ),
  );

  Stream<Map<String, dynamic>> get toolEvents => AgentEventBus.instance.events;
  void beginAgentRequest(String requestId) => _activeRequestId = requestId;
  void endAgentRequest(String requestId) { if (_activeRequestId == requestId) _activeRequestId = ''; }

  void _emitToolEvent(String type, String title, {
    String? toolName,
    String? path,
    String? content,
    String? output,
    String? details,
    String? status,
    String? stepId,
  }) {
    final sequence = ++_toolEventSequence;
    AgentEventBus.instance.publish({
      'id': 'tool_${_activeRequestId}_event_$sequence',
      'request_id': _activeRequestId,
      'attempt_id': _activeRequestId,
      'step_id': stepId ?? 'tool_${_activeRequestId}_$sequence',
      'sequence': sequence,
      'type': type,
      'title': title,
      'tool_name': toolName,
      'file_name': path,
      'content': content,
      'output': output,
      'details': details,
      'status': status ?? 'completed',
      'timestamp': DateTime.now().toIso8601String(),
    }..removeWhere((key, value) => value == null || value == ''));
  }

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

  Future<Map<String, dynamic>> _executeTool(
    Map<String, dynamic> payload, {
    String? stepId,
  }) async {
    final name = payload['name']?.toString() ?? '';
    if (!ToolManager().supports(name)) {
      throw FormatException('Unsupported tool: $name');
    }
    final args = payload['arguments'];
    if (args is! Map<String, dynamic>) {
      throw const FormatException('Tool arguments must be an object.');
    }
    final path = args['path']?.toString() ?? '';
    final content = args['content']?.toString() ?? '';
    final toolStepId = stepId ?? 'tool_step_${_activeRequestId}_${DateTime.now().microsecondsSinceEpoch}';
    _emitToolEvent('tool_start', _toolStartTitle(name), toolName: name, path: path,
        content: name == 'execute_python' ? args['code']?.toString() : null, status: 'running', stepId: toolStepId);
    try {
      late final Map<String, dynamic> result;
      switch (name) {
        case 'create_file':
          result = await createFile(path: path, content: content);
          break;
        case 'read_file':
          result = await readFile(path: path);
          break;
        case 'write_file':
          result = await writeFile(path: path, content: content);
          break;
        case 'list_files':
          result = <String, dynamic>{
            'ok': true,
            'files': await listWorkspaceFiles(),
          };
          break;
        case 'execute_python':
          result = await executePython(code: args['code']?.toString() ?? '');
          break;
        default:
          throw FormatException('Unsupported tool: $name');
      }
      final ok = result['ok'] == true;
      final output = (result['output'] ?? result['path'] ?? result['error'] ?? result).toString();
      if (ok && name == 'create_file') {
        _emitToolEvent('file_created', 'تم إنشاء الملف', toolName: name, path: path,
            output: output, details: 'أنشأ المحرك الملف داخل مساحة العمل فعلياً.', stepId: toolStepId);
      } else if (ok && name == 'write_file') {
        _emitToolEvent('file_updated', 'تم تحديث الملف', toolName: name, path: path,
            output: output, details: 'حُفظت التغييرات في مساحة العمل فعلياً.', stepId: toolStepId);
      }
      _emitToolEvent(ok ? 'tool_output' : 'tool_error',
          ok ? _toolCompleteTitle(name) : 'فشل تنفيذ الأداة',
          toolName: name, path: path, output: output,
          details: ok ? null : result['error']?.toString(),
          status: ok ? 'completed' : 'failed', stepId: toolStepId);
      return result;
    } catch (error) {
      _emitToolEvent('tool_error', 'فشل تنفيذ الأداة', toolName: name,
          path: path, output: error.toString(), status: 'failed', stepId: toolStepId);
      rethrow;
    }
  }

  String _toolStartTitle(String name) {
    switch (name) {
      case 'create_file': return 'ينشئ ملفاً في مساحة العمل';
      case 'write_file': return 'يحدّث ملفاً موجوداً';
      case 'read_file': return 'يقرأ ملفاً من مساحة العمل';
      case 'execute_python': return 'يشغّل كود Python';
      case 'list_files': return 'يعرض ملفات مساحة العمل';
      default: return 'ينفّذ أداة';
    }
  }

  String _toolCompleteTitle(String name) {
    switch (name) {
      case 'create_file': return 'اكتمل إنشاء الملف';
      case 'write_file': return 'اكتمل تحديث الملف';
      case 'read_file': return 'اكتملت قراءة الملف';
      case 'execute_python': return 'اكتمل تنفيذ Python';
      case 'list_files': return 'اكتمل استعراض الملفات';
      default: return 'اكتمل تنفيذ الأداة';
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

  /// Direct conversational path: no AgentKernel orchestration and no tool loop.
  /// The local model (or configured OpenAI-compatible provider) answers normally.
  Future<String> processChat(
    String input, {
    String conversationId = 'global',
  }) {
    return _withRuntimeLock(() async {
      final context = await AgentMemoryService.instance.buildContext(
        input,
        conversationId: conversationId,
      );
      final prompt = context.isEmpty ? input : '$context\n\nرسالة المستخدم: $input';
      final response = await _generateText(
        _boundPrompt(prompt),
        maxTokens: 768,
        temperature: .35,
      );
      await AgentMemoryService.instance.saveTurn(
        input,
        response,
        conversationId: conversationId,
      );
      return response.trim();
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
    final mode = await ModelProviderSettings.instance.getMode();
    switch (mode) {
      case ModelProviderMode.local:
        if (!await _llama.isLoaded()) {
          throw StateError('لم يتم تحميل نموذج GGUF المحلي. حمّل نموذجاً من قائمة النماذج أو اختر مزوّداً سحابياً.');
        }
        return _llama.generate(prompt, maxTokens: maxTokens, temperature: temperature);
      case ModelProviderMode.openRouter:
        return OpenAICompatibleProvider.instance.generate(
          prompt, maxTokens: maxTokens, temperature: temperature,
        );
      case ModelProviderMode.gemini:
        return GeminiProvider.instance.generate(
          prompt, maxTokens: maxTokens, temperature: temperature,
        );
    }
  }

  Future<String> _processInput(String input) async {
    _cancelRequested = false;
    input = _boundPrompt(input);
    if (await ModelProviderSettings.instance.getMode() == ModelProviderMode.local && !await _llama.isLoaded()) {
      return '⚠️ لم يتم تحميل نموذج GGUF المحلي. حمّل نموذجاً أو اختر OpenRouter أو Gemini من إعدادات المزوّد.';
    }
    final toolCatalog = ToolManager().promptCatalog;
    final history = StringBuffer('''أنت Giant Agent، مساعد ذكي متعدد المصادر. أجب بلغة المستخدم.
الأدوات المتاحة فعلياً:
$toolCatalog
عندما تتطلب المهمة تسليم شيء قابل للاستخدام خارج المحادثة (مثل صفحة ويب، نموذج تفاعلي، مشروع برمجي، سكربت، تقرير، جدول بيانات، ملف إعدادات أو مستند)، أنشئ المخرج كملف حقيقي داخل مساحة العمل باستخدام create_file، ولا تكتفِ بعرض الكود أو وصف ما ستفعله. اختر امتداداً مناسباً للمخرج (مثل html أو dart أو py أو md أو csv أو json). في صفحات الويب أنشئ index.html مكتملاً بـ HTML وCSS وJavaScript مضمّنة، متجاوباً ويعمل دون CDN أو اعتماد على الشبكة. للمشاريع متعددة الملفات أنشئ الملفات اللازمة واحداً تلو الآخر ضمن حدود الأدوات. إذا كان الملف موجوداً فاقرأه أولاً ثم حدّثه عبر write_file، ولا تستبدله عبر create_file. بعد الإنشاء أو التحديث، استخدم read_file للتحقق من وجود المحتوى النهائي عند الإمكان. أظهر للمستخدم اسم الملف ومساره وما تم التحقق منه، ولا تدّع إنشاء ملف أو تشغيل مشروع ما لم تؤكد نتيجة الأداة ذلك. لا تنشئ ملفات لأسئلة المعرفة أو الشرح العادي أو عندما يكون الرد النصي وحده هو المخرج الأنسب. إذا طلب المستخدم مشروع Flutter أصلياً، أنشئ ملفات Dart المناسبة ولا تدّع أن WebView تستطيع تشغيلها؛ فهي تعرض الكود فقط.
عند الحاجة لاستخدام أداة أخرج استدعاءً واحداً فقط بالصيغة التالية، مع اسم أداة موجود في القائمة أعلاه ووسائط مطابقة لمثالها:
<tool_call>{"name":"tool_name","arguments":{}}</tool_call>
لا تدّع نجاح أي عملية قبل استلام نتيجة الأداة. إذا كانت النتيجة ok=false فاشرح الفشل ولا تعلن النجاح. لا تطلب أدوات إذا لم تكن لازمة.
إذا كان الطلب سؤالاً مباشراً أو شرحاً أو مراجعة/تصحيحاً بسيطاً لمقطع كود أرسله المستخدم، فأجب مباشرة في المحادثة دون إنشاء خطة أو استدعاء أدوات. لا تنشئ أو تعدّل ملفات ولا تشغّل أدوات إلا إذا طلب المستخدم ذلك صراحة أو كانت الأداة ضرورية لإنجاز المطلوب.
لا تعرض التفكير الداخلي التفصيلي.

المستخدم: $input

المساعد:''');
    try {
      final executedCalls = <String>{};
      const maxToolCalls = 16;
      const maxReflexionAttempts = 3;
      var reflexionAttempts = 0;
      Map<String, dynamic>? pendingReflexionPayload;

      for (var step = 0; step < maxToolCalls; step++) {
        if (_cancelRequested) return 'تم إيقاف تنفيذ الوكيل بناءً على طلب المستخدم.';

        Map<String, dynamic> payload;
        if (pendingReflexionPayload != null) {
          payload = pendingReflexionPayload;
          pendingReflexionPayload = null;
        } else {
          final generated = await _generateText(history.toString(), maxTokens: 768, temperature: .25);
          if (_cancelRequested) {
            return generated.trim().isEmpty
                ? 'تم إيقاف التوليد.'
                : '${generated.trim()}\n\n[تم إيقاف التوليد]';
          }
          final match = RegExp(r'<tool_call>\s*(\{.*?\})\s*</tool_call>', dotAll: true)
              .firstMatch(generated);
          if (match == null) return generated.trim();
          final decoded = jsonDecode(match.group(1)!);
          if (decoded is! Map<String, dynamic>) {
            return 'تعذر تحليل استدعاء الأداة: يجب أن تكون البيانات كائن JSON.';
          }
          payload = decoded;
        }

        final toolName = payload['name']?.toString() ?? '';
        final rawArgs = payload['arguments'];
        if (!ToolManager().supports(toolName) || rawArgs is! Map<String, dynamic>) {
          history
            ..write('\n\nSystem Note: Unsupported tool or invalid arguments. Use only the registered tool catalogue.\n\nAssistant:');
          continue;
        }

        final signature = jsonEncode(payload);
        if (!executedCalls.add(signature)) {
          _emitToolEvent(
            'reflexion_failed',
            'أوقف الوكيل محاولة تكرار الإجراء نفسه',
            toolName: toolName,
            details: 'The proposed recovery action duplicates an action already attempted.',
            status: 'failed',
          );
          return 'تعذر إكمال الهدف بأمان: اقترح محرك التأمل إجراءً مكرراً، فأوقفته آلية منع التكرار.';
        }

        final toolStepId = 'verified_step_${_activeRequestId}_${DateTime.now().microsecondsSinceEpoch}';
        Map<String, dynamic> result;
        try {
          result = await _executeTool(payload, stepId: toolStepId);
        } catch (error) {
          result = <String, dynamic>{'ok': false, 'error': error.toString()};
        }
        if (_cancelRequested) return 'تم إيقاف الوكيل بعد اكتمال الأداة الحالية.';

        _emitToolEvent(
          'verification_started',
          'يتحقق من النتيجة الفعلية',
          toolName: toolName,
          details: 'التحقق من أثر الأداة داخل مساحة العمل، وليس من رسالة النموذج.',
          status: 'running',
          stepId: toolStepId,
        );
        final verification = await _evaluator.verify(
          input,
          toolName,
          rawArgs,
          result,
        );
        _emitToolEvent(
          verification.passed ? 'verification_passed' : 'verification_failed',
          verification.passed ? 'اجتاز التحقق المستقل' : 'فشل التحقق المستقل',
          toolName: toolName,
          output: jsonEncode(verification.evidence ?? const <String, Object?>{}),
          details: verification.message,
          status: verification.passed ? 'completed' : 'failed',
          stepId: toolStepId,
        );

        if (!verification.passed) {
          final failedAction = jsonEncode(payload);
          history
            ..write('\n\nSystem Note: Tool $toolName result: ${jsonEncode(result)}')
            ..write('\nIndependent verification FAILED: ${verification.message}')
            ..write('\nDo not claim the goal is complete. Choose a different corrective tool action.\n\nAssistant:');

          if (reflexionAttempts >= maxReflexionAttempts) {
            return 'لم يتحقق الهدف بعد $maxReflexionAttempts محاولات تصحيح آمنة. آخر نتيجة: ${verification.message}';
          }

          _emitToolEvent(
            'reflexion_started',
            'يحلل فشل التحقق ويختار إجراءً بديلاً',
            toolName: toolName,
            details: 'محاولة التصحيح ${reflexionAttempts + 1} من $maxReflexionAttempts.',
            status: 'running',
            stepId: toolStepId,
          );
          try {
            final action = await _reflexion.generateFix(
              originalGoal: input,
              failedAction: failedAction,
              errorMessage: verification.message,
            );
            final proposed = <String, dynamic>{
              'name': action.toolName,
              'arguments': action.arguments,
            };
            final proposedSignature = jsonEncode(proposed);
            if (proposedSignature == signature || executedCalls.contains(proposedSignature)) {
              throw const FormatException('Reflexion proposed an action that has already been attempted.');
            }
            pendingReflexionPayload = proposed;
            reflexionAttempts++;
            _emitToolEvent(
              'reflexion_action_proposed',
              'اختير إجراء تصحيحي بديل',
              toolName: action.toolName,
              output: jsonEncode(action.arguments),
              details: 'سيُنفذ الإجراء بعد التحقق من سماح الأداة وصحة بنية الوسائط.',
              status: 'completed',
              stepId: toolStepId,
            );
          } catch (error) {
            _emitToolEvent(
              'reflexion_failed',
              'تعذر توليد إجراء تصحيحي آمن',
              toolName: toolName,
              details: error.toString(),
              status: 'failed',
              stepId: toolStepId,
            );
            return 'فشل التحقق من النتيجة، ولم يتمكن محرك التأمل من اقتراح إجراء بديل صالح: $error';
          }
          continue;
        }

        final resultJson = jsonEncode(result);
        final pythonTail = result['output']?.toString() ?? '';
        final boundedPythonTail = pythonTail.length > 500
            ? '${pythonTail.substring(pythonTail.length - 500)}\n[Python output truncated to last 500 characters]'
            : pythonTail;
        final contextResult = toolName == 'execute_python'
            ? 'ok=true\n$boundedPythonTail'
            : resultJson;
        history
          ..write('\n\nSystem Note: $toolName result (independently verified): ')
          ..write(contextResult)
          ..write('\nContinue only if more work is required; never claim unverified side effects.\n\nAssistant:');
      }
      return 'وصل الوكيل إلى الحد الآمن ($maxToolCalls دورات تنفيذ/تحقق) دون إنهاء المهمة. أعد الطلب لمتابعة العمل من سياق المحادثة.';
    } catch (e) {
      return 'تعذر إكمال الطلب: $e';
    }
  }
}
