import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import '../services/llama_service.dart';
import '../services/web_search_service.dart';
import '../services/browser_session_service.dart';
import '../services/voice_output_service.dart';
import '../agent/task_manager.dart';
import '../agent/architecture/agent_event_bus.dart';
import '../agent/architecture/tool_call_registry.dart';
import '../agent/architecture/subagent_lifecycle_manager.dart';
import 'agent_memory_service.dart';
import 'openai_compatible_provider.dart';
import 'model_provider_settings.dart';
import '../tools/tool_manager.dart';
import '../tools/gain_terminal_tool.dart';
import '../tools/terminal_tool_coordinator.dart';
import '../domain/harness/evaluator_service.dart';
import '../domain/harness/reflexion_service.dart';
import '../domain/mcp/mcp_client.dart';

typedef AgentUserInputHandler = Future<String?> Function({required String question, required List<String> choices});

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
  Future<bool> Function(String serverId, McpRemoteTool tool, Map<String, dynamic> arguments)? requestMcpApproval;
  AgentUserInputHandler? requestUserInput;
  Future<void> Function()? requestBrowserSession;
  late final SubagentLifecycleManager _subagents = SubagentLifecycleManager(onEvent: AgentEventBus.instance.publish);
  final GainTerminalTool _gainTerminal = GainTerminalTool();
  Future<void> _requestTail = Future<void>.value();
  Future<void> _toolTail = Future<void>.value();
  String _fallbackRequestId = '';
  int _parallelExecutions = 0;
  int _toolEventSequence = 0;
  final ToolCallRegistry _toolCalls = ToolCallRegistry();
  static const Object _requestIdZoneKey = #giantAgentRequestId;
  static const Object _parallelProviderZoneKey = #giantAgentParallelProvider;
  static const Object _taskIdZoneKey = #giantAgentTaskId;
  static const Object _agentTypeZoneKey = #giantAgentAgentType;
  static const Object _conversationIdZoneKey = #giantAgentConversationId;
  static const Object _toolLockOwnerZoneKey = #giantAgentToolLockOwner;
  Object? _activeToolLockOwner;
  String get _activeTaskId => Zone.current[_taskIdZoneKey] as String? ?? '';
  String get _activeAgentType => Zone.current[_agentTypeZoneKey] as String? ?? '';
  String get _activeConversationId => Zone.current[_conversationIdZoneKey] as String? ?? 'global';
  String get _activeRequestId =>
      Zone.current[_requestIdZoneKey] as String? ?? _fallbackRequestId;

  late final EvaluatorService _evaluator = EvaluatorService(
    readWorkspaceFile: (path) => readFile(path: path),
  );
  late final ReflexionService _reflexion = ReflexionService(
    generate: (String prompt, {bool Function()? shouldCancel}) => _generateText(
      _boundPrompt(prompt),
      maxTokens: 512,
      temperature: .1,
      shouldCancel: shouldCancel,
    ),
  );

  Stream<Map<String, dynamic>> get toolEvents => AgentEventBus.instance.events;
  void beginAgentRequest(String requestId) {
    _fallbackRequestId = requestId;
    _cancelRequested = false;
  }

  void endAgentRequest(String requestId) {
    if (_fallbackRequestId == requestId) {
      _fallbackRequestId = '';
      _cancelRequested = false;
    }
  }

  void _emitToolEvent(String type, String title, {
    String? toolName,
    String? path,
    String? content,
    String? output,
    String? details,
    String? status,
    String? stepId,
    String? toolCallId,
  }) {
    final sequence = ++_toolEventSequence;
    AgentEventBus.instance.publish({
      'id': 'tool_${_activeRequestId}_event_$sequence',
      'request_id': _activeRequestId,
      'attempt_id': _activeRequestId,
      'task_id': _activeTaskId,
      'agent_type': _activeAgentType,
      'step_id': stepId ?? 'tool_${_activeRequestId}_$sequence',
      'tool_call_id': toolCallId,
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
  Future<T> _withToolLock<T>(Future<T> Function() operation) async {
    final inheritedOwner = Zone.current[_toolLockOwnerZoneKey];
    if (inheritedOwner != null && identical(inheritedOwner, _activeToolLockOwner)) {
      return operation();
    }
    final gate = Completer<void>();
    final previous = _toolTail;
    _toolTail = gate.future;
    await previous;
    final owner = Object();
    _activeToolLockOwner = owner;
    try {
      return await runZoned(operation, zoneValues: <Object, Object?>{_toolLockOwnerZoneKey: owner});
    } finally {
      if (identical(_activeToolLockOwner, owner)) _activeToolLockOwner = null;
      if (!gate.isCompleted) gate.complete();
    }
  }

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
  bool get isBusy => _isLoading || _parallelExecutions > 0;
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

  bool cancelToolCall(String toolCallId) => _toolCalls.cancel(toolCallId);

  Future<bool> cancelGeneration() async {
    _cancelRequested = true;
    final mode = await ModelProviderSettings.instance.getMode();
    if (mode == ModelProviderMode.openRouter) return true;
    return _llama.cancel();
  }

  Future<bool> shareWorkspace({required List<String> paths}) async {
    if (paths.isEmpty) throw ArgumentError('Select at least one output file to share.');
    final result = await _agentTools.invokeMapMethod<String, dynamic>(
      'shareWorkspace', <String, Object?>{'paths': paths},
    );
    if (result == null || result['ok'] != true) {
      throw PlatformException(code: 'WORKSPACE_SHARE_FAILED', message: result?['error']?.toString() ?? 'Workspace sharing failed.');
    }
    return true;
  }

  Future<bool> openWorkspaceFile({required String path}) async {
    final opened = await _agentTools.invokeMethod<bool>('openWorkspaceFile', {'path': path});
    if (opened != true) {
      throw PlatformException(code: 'WORKSPACE_FILE_OPEN_FAILED', message: 'Unable to open workspace file.');
    }
    return true;
  }

  Future<Map<String, dynamic>> inspectWorkspaceFile({required String path}) async {
    final result = await _agentTools.invokeMapMethod<String, dynamic>('inspectWorkspaceFile', {'path': path});
    if (result == null || result['ok'] != true) {
      throw PlatformException(code: 'WORKSPACE_FILE_INSPECT_FAILED', message: 'Unable to verify workspace artifact.');
    }
    return result;
  }

  Future<Map<String, dynamic>> readImagePreview({required String path}) async {
    final result = await _agentTools.invokeMapMethod<String, dynamic>('readImagePreview', {'path': path});
    if (result == null || result['ok'] != true || result['base64'] == null) {
      throw PlatformException(code: 'IMAGE_PREVIEW_FAILED', message: 'Unable to load image preview.');
    }
    return result;
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

  Future<Map<String, dynamic>> _executeToolUnlocked(
    Map<String, dynamic> payload, {
    String? stepId,
    Set<String>? allowedTools,
    bool Function()? isCancelled,
  }) async {
    final name = payload['name']?.toString() ?? '';
    if (!ToolManager().supports(name) ||
        (allowedTools != null && !allowedTools.contains(name))) {
      throw FormatException('Unsupported tool: $name');
    }
    final args = payload['arguments'];
    if (args is! Map<String, dynamic>) {
      throw const FormatException('Tool arguments must be an object.');
    }
    final path = args['path']?.toString() ?? '';
    final content = args['content']?.toString() ?? '';
    final toolStepId = stepId ?? 'tool_step_${_activeRequestId}_${DateTime.now().microsecondsSinceEpoch}';
    if (name != 'gain_terminal') {
      _emitToolEvent('tool_start', _toolStartTitle(name), toolName: name, path: path,
          content: name == 'execute_python' ? args['code']?.toString() : null, status: 'running', stepId: toolStepId);
    }
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
        case 'mcp_read_resource':
          final serverId = args['server_id']?.toString() ?? '';
          final resourceUri = args['uri']?.toString() ?? '';
          if (serverId.isEmpty || resourceUri.isEmpty) {
            throw const FormatException('mcp_read_resource requires server_id and uri.');
          }
          final resourceResult = await McpClient.instance.readResource(
            serverId: serverId,
            uri: resourceUri,
            isCancelled: isCancelled,
          );
          result = <String, dynamic>{
            'ok': true,
            'resource_result': resourceResult,
          };
          break;
        case 'mcp_call':
          final serverId = args['server_id']?.toString() ?? '';
          final remoteToolName = args['tool_name']?.toString() ?? '';
          final remoteArguments = args['arguments'];
          if (serverId.isEmpty || remoteToolName.isEmpty || remoteArguments is! Map<String, dynamic>) {
            throw const FormatException('mcp_call requires server_id, tool_name and an arguments object.');
          }
          final remoteTool = await McpClient.instance.findTool(serverId, remoteToolName);
          final readOnlyHint = remoteTool.annotations['readOnlyHint'] == true &&
              remoteTool.annotations['destructiveHint'] != true &&
              remoteTool.annotations['openWorldHint'] != true;
          if (!readOnlyHint) {
            final approval = requestMcpApproval;
            if (approval == null ||
                !await approval(serverId, remoteTool, remoteArguments)) {
              result = <String, dynamic>{
                'ok': false,
                'denied': true,
                'error': 'MCP tool requires explicit user approval; no approval was granted.',
              };
              break;
            }
          }
          final mcpResult = await McpClient.instance.callTool(
            serverId: serverId,
            toolName: remoteToolName,
            arguments: remoteArguments,
            isCancelled: isCancelled,
          );
          result = <String, dynamic>{
            'ok': !mcpResult.isError,
            'isError': mcpResult.isError,
            'textPreview': mcpResult.textPreview,
            'mcp_result': mcpResult.toJson(),
            if (mcpResult.structuredContent != null) 'structuredContent': mcpResult.structuredContent,
          };
          break;
        case 'create_subagent':
          if (_activeTaskId.isNotEmpty) {
            throw StateError('A child agent cannot create another child agent.');
          }
          final rawDependencies = args['depends_on'] ?? const <dynamic>[];
          if (rawDependencies is! List || rawDependencies.any((item) => item is! String)) {
            throw const FormatException('depends_on must be a list of agent ids.');
          }
          final created = await _subagents.create(
            requestId: _activeRequestId,
            conversationId: _activeConversationId,
            id: args['id']?.toString() ?? '',
            title: args['title']?.toString() ?? '',
            prompt: args['prompt']?.toString() ?? '',
            agentType: args['agent_type']?.toString() ?? 'explore',
            dependsOn: rawDependencies.map((item) => item.toString()).toList(),
            creatorTaskId: _activeTaskId,
          );
          result = <String, dynamic>{'ok': true, 'subagent': created.toMap()};
          break;
        case 'spawn_subagent':
          result = await _spawnDynamicSubagent(
            args['id']?.toString() ?? '',
            isCancelled: isCancelled,
          );
          break;
        case 'delete_subagent':
          final agentId = args['id']?.toString() ?? '';
          await _subagents.delete(_activeRequestId, agentId);
          final deleted = _subagents.get(_activeRequestId, agentId);
          result = <String, dynamic>{'ok': deleted != null && deleted.dismissed, 'subagent': deleted?.toMap()};
          break;
        case 'check_subagent_status':
          final agentId = args['id']?.toString() ?? '';
          final snapshot = _subagents.get(_activeRequestId, agentId);
          if (snapshot == null) throw StateError('Subagent not found: $agentId');
          result = <String, dynamic>{'ok': true, 'subagent': snapshot.toMap()};
          break;
        case 'send_message':
          final agentId = args['agent_id']?.toString() ?? '';
          await _subagents.sendMessage(
            requestId: _activeRequestId,
            agentId: agentId,
            message: args['message']?.toString() ?? '',
            senderTaskId: _activeTaskId.isEmpty ? null : _activeTaskId,
          );
          result = <String, dynamic>{'ok': true, 'message_queued': true, 'agent_id': agentId};
          break;
        case 'wait_for_message':
          final agentId = args['agent_id']?.toString() ?? '';
          final timeout = args['timeout_seconds'] is int ? args['timeout_seconds'] as int : 10;
          final message = await _subagents.waitForMessage(
            requestId: _activeRequestId,
            agentId: agentId,
            timeoutSeconds: timeout,
          );
          result = <String, dynamic>{
            'ok': true,
            'received': message != null,
            if (message != null) 'message': message,
            if (message == null) 'timed_out': true,
          };
          break;
        case 'ask_user':
          if (_activeTaskId.isNotEmpty) {
            throw StateError('Only the coordinating agent may ask the user.');
          }
          final question = args['question']?.toString().trim() ?? '';
          final rawChoices = args['choices'] ?? const <dynamic>[];
          if (question.isEmpty || question.length > 1000 ||
              rawChoices is! List || rawChoices.length > 6 ||
              rawChoices.any((item) => item is! String)) {
            throw const FormatException('ask_user requires a question and up to six string choices.');
          }
          final handler = requestUserInput;
          if (handler == null) {
            result = <String, dynamic>{'ok': false, 'error': 'User input UI is unavailable; no answer was fabricated.'};
            break;
          }
          final answer = await handler(
            question: question,
            choices: rawChoices.map((item) => item.toString()).toList(),
          );
          result = <String, dynamic>{'ok': true, 'cancelled': answer == null, if (answer != null) 'answer': answer};
          break;
        case 'update_goal':
          if (_activeTaskId.isNotEmpty) {
            throw StateError('Only the coordinating agent may update the request goal.');
          }
          final goal = args['goal']?.toString() ?? '';
          await _subagents.updateGoal(_activeRequestId, goal);
          result = <String, dynamic>{'ok': true, 'goal': _subagents.currentGoal(_activeRequestId)};
          break;
        case 'web_search':
          final query = args['query']?.toString() ?? '';
          final limit = args['limit'] is int ? (args['limit'] as int).clamp(1, 8).toInt() : 5;
          final searchResults = await WebSearchService.instance.search(query, limit: limit);
          result = <String, dynamic>{'ok': true, 'query': query, 'results': searchResults};
          break;
        case 'todo_read':
          final status = args['status']?.toString();
          final tasks = await TaskManager().getTasksForConversation(
            _activeConversationId,
            status: status == null || status.isEmpty ? null : status,
          );
          result = <String, dynamic>{'ok': true, 'tasks': tasks};
          break;
        case 'todo_write':
          final description = args['description']?.toString() ?? '';
          final task = await TaskManager().createTask(
            description,
            conversationId: _activeConversationId,
          );
          result = <String, dynamic>{'ok': true, 'task': task, 'execution_started': false};
          break;
        case 'memory_space_insert':
          final memoryKey = args['key']?.toString() ?? '';
          final memoryValue = args['value']?.toString() ?? '';
          final importance = args['importance'] is int ? args['importance'] as int : 1;
          await AgentMemoryService.instance.remember(
            memoryKey, memoryValue, importance: importance,
          );
          result = <String, dynamic>{'ok': true, 'key': memoryKey, 'stored': true};
          break;
        case 'memory_space_update':
          final memoryKey = args['key']?.toString() ?? '';
          final memoryValue = args['value']?.toString() ?? '';
          final importance = args['importance'] is int ? args['importance'] as int? : null;
          final updated = await AgentMemoryService.instance.updateFact(
            memoryKey, memoryValue, importance: importance,
          );
          result = <String, dynamic>{
            'ok': updated,
            'key': memoryKey,
            if (!updated) 'error': 'Memory key does not exist; use memory_space_insert first.',
          };
          break;
        case 'memory_space_delete':
          final memoryKey = args['key']?.toString() ?? '';
          final deleted = await AgentMemoryService.instance.deleteFact(memoryKey);
          result = <String, dynamic>{
            'ok': deleted,
            'key': memoryKey,
            if (!deleted) 'error': 'Memory key does not exist.',
          };
          break;
        case 'memory_space_edits':
          final limit = args['limit'] is int ? (args['limit'] as int).clamp(1, 500).toInt() : 100;
          result = <String, dynamic>{
            'ok': true,
            'facts': await AgentMemoryService.instance.getFacts(limit: limit),
            'edits': await AgentMemoryService.instance.getFactEdits(limit: limit),
          };
          break;
        case 'generate_speech':
          final speechText = args['text']?.toString() ?? '';
          if (speechText.trim().isEmpty) throw const FormatException('Speech text must not be empty.');
          await VoiceOutputService.instance.speak(speechText, waitForCompletion: true);
          result = <String, dynamic>{
            'ok': true,
            'played': true,
            'saved_audio_file': false,
            'message': 'تم تشغيل النص عبر محرك TTS في الجهاز.',
          };
          break;
        case 'get_available_voices':
          result = <String, dynamic>{
            'ok': true,
            'voices': await VoiceOutputService.instance.getAvailableVoices(),
          };
          break;
        case 'get_data_source':
          final servers = await McpClient.instance.servers();
          result = <String, dynamic>{
            'ok': true,
            'servers': servers.map((server) => <String, dynamic>{
              'id': server.id,
              'name': server.name,
              'host': Uri.parse(server.endpoint).host,
            }).toList(growable: false),
          };
          break;
        case 'get_data_source_desc':
          final serverId = args['server_id']?.toString() ?? '';
          final servers = await McpClient.instance.servers();
          McpServerConfig? selected;
          for (final server in servers) {
            if (server.id == serverId) { selected = server; break; }
          }
          if (selected == null) throw StateError('MCP data source is not configured: $serverId');
          final info = await McpClient.instance.initialize(serverId, isCancelled: isCancelled);
          final tools = await McpClient.instance.listTools(serverId, isCancelled: isCancelled);
          final resources = await McpClient.instance.listResources(serverId, isCancelled: isCancelled);
          result = <String, dynamic>{
            'ok': true,
            'server': <String, dynamic>{
              'id': selected.id,
              'name': selected.name,
              'host': Uri.parse(selected.endpoint).host,
              'server_info': info,
            },
            'tools': tools.map((tool) => <String, dynamic>{
              'name': tool.name,
              'description': tool.description,
              'input_schema': tool.inputSchema,
              'annotations': tool.annotations,
            }).toList(growable: false),
            'resources': resources,
          };
          break;
        case 'generate_slides_outline':
          final topic = args['topic']?.toString().trim() ?? '';
          final count = args['slides'] is int ? (args['slides'] as int).clamp(3, 20).toInt() : 8;
          if (topic.isEmpty) throw const FormatException('A slide topic is required.');
          final outline = await _generateText(
            _boundPrompt('''أنشئ مخطط عرض تقديمي من $count شرائح حول الموضوع التالي: $topic
أعد JSON صالحاً فقط بالشكل {"title":"...","slides":[{"title":"...","bullets":["..."]}]}.
اجعل المحتوى موجزاً ودقيقاً، ولا تخترع بيانات أو مصادر.'''),
            maxTokens: 1200,
            temperature: .2,
            shouldCancel: isCancelled,
          );
          result = <String, dynamic>{'ok': outline.trim().isNotEmpty, 'outline': outline.trim()};
          break;
        case 'slides_generator':
          final slidePath = args['path']?.toString() ?? '';
          final presentationTitle = args['title']?.toString() ?? 'Giant Agent Presentation';
          final rawSlides = args['slides'];
          if (slidePath.trim().isEmpty || rawSlides is! List ||
              rawSlides.isEmpty || rawSlides.length > 40 ||
              rawSlides.any((slide) => slide is! Map)) {
            throw const FormatException('slides_generator requires a path and 1–40 slide objects.');
          }
          final escape = const HtmlEscape();
          final buffer = StringBuffer('''<!doctype html>
<html lang="ar"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escape.convert(presentationTitle)}</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#0b1220;color:#e5edf7;font-family:Arial,sans-serif}
.deck{min-height:100vh;display:grid;place-items:center;padding:24px}
.slide{display:none;width:min(1100px,96vw);min-height:min(680px,88vh);padding:clamp(24px,6vw,72px);border:1px solid #334155;border-radius:24px;background:linear-gradient(145deg,#17243a,#101827);box-shadow:0 24px 70px #0008}
.slide.active{display:block}.slide h1{font-size:clamp(30px,5vw,56px);color:#5eead4;margin:0 0 28px}
.slide p,.slide li{font-size:clamp(18px,2.4vw,28px);line-height:1.6}
.controls{position:fixed;bottom:18px;left:0;right:0;display:flex;justify-content:center;gap:12px}
button{border:0;border-radius:12px;padding:12px 20px;background:#2563eb;color:white;font-size:16px}
.counter{position:fixed;top:18px;right:22px;color:#94a3b8}
</style></head><body><div class="counter" id="counter"></div><main class="deck">''');
          for (var index = 0; index < rawSlides.length; index++) {
            final slide = Map<String, dynamic>.from(rawSlides[index] as Map);
            final slideTitle = escape.convert(slide['title']?.toString() ?? 'Slide ${index + 1}');
            final body = slide['body']?.toString() ?? '';
            final bullets = slide['bullets'];
            buffer.write('<section class="slide${index == 0 ? ' active' : ''}"><h1>$slideTitle</h1>');
            if (bullets is List && bullets.isNotEmpty) {
              buffer.write('<ul>');
              for (final bullet in bullets.take(12)) {
                buffer.write('<li>${escape.convert(bullet.toString())}</li>');
              }
              buffer.write('</ul>');
            } else if (body.isNotEmpty) {
              buffer.write('<p>${escape.convert(body)}</p>');
            }
            buffer.write('</section>');
          }
          buffer.write('''</main><nav class="controls"><button id="prev">السابق</button><button id="next">التالي</button></nav>
<script>
const slides=[...document.querySelectorAll('.slide')];let current=0;
function show(n){current=Math.max(0,Math.min(slides.length-1,n));slides.forEach((s,i)=>s.classList.toggle('active',i===current));document.getElementById('counter').textContent=(current+1)+' / '+slides.length;}
document.getElementById('prev').onclick=()=>show(current-1);document.getElementById('next').onclick=()=>show(current+1);
document.addEventListener('keydown',e=>{if(e.key==='ArrowRight'||e.key==='ArrowDown')show(current+1);if(e.key==='ArrowLeft'||e.key==='ArrowUp')show(current-1);});show(0);
</script></body></html>''');
          final created = await createFile(path: slidePath, content: buffer.toString());
          result = <String, dynamic>{
            'ok': true,
            'path': slidePath,
            'slide_count': rawSlides.length,
            'created_file': created,
            'format': 'self-contained HTML slides',
            'powerpoint_file_created': false,
          };
          break;
        case 'fetch_urls':
          final rawUrls = args['urls'];
          if (rawUrls is! List || rawUrls.isEmpty || rawUrls.length > 5 ||
              rawUrls.any((item) => item is! String)) {
            throw const FormatException('fetch_urls accepts a list of 1–5 HTTP(S) URLs.');
          }
          await _ensureBrowserSession();
          final fetched = await BrowserSessionService.instance.fetchUrls(
            rawUrls.map((item) => item.toString()).toList(),
          );
          result = <String, dynamic>{'ok': fetched.isNotEmpty && fetched.every((item) => item['ok'] == true), 'results': fetched};
          break;
        case 'visit':
        case 'browser_visit':
          await _ensureBrowserSession();
          result = await BrowserSessionService.instance.visit(args['url']?.toString() ?? '');
          break;
        case 'click':
        case 'browser_click':
          result = await BrowserSessionService.instance.click(
            args['text']?.toString() ?? '',
          );
          break;
        case 'input':
        case 'browser_input':
          result = await BrowserSessionService.instance.input(
            args['selector']?.toString() ?? '',
            args['value']?.toString() ?? '',
          );
          break;
        case 'find':
        case 'browser_find':
          result = await BrowserSessionService.instance.find(
            args['query']?.toString() ?? '',
          );
          break;
        case 'scrollup':
        case 'browser_scroll_up':
          result = await BrowserSessionService.instance.scroll(down: false);
          break;
        case 'scrolldown':
        case 'browser_scroll_down':
          result = await BrowserSessionService.instance.scroll(down: true);
          break;
        case 'browser_state':
          result = await BrowserSessionService.instance.state();
          break;
        case 'gain_terminal':
          final approval = requestTerminalApproval;
          if (approval == null) {
            result = <String, dynamic>{'ok': false, 'denied': true, 'error': 'Terminal approval UI is unavailable.'};
            break;
          }
          final coordinator = TerminalToolCoordinator(
            requestApproval: approval,
            execute: (command, timeout) => _gainTerminal.execute(command, timeout: timeout),
            onEvent: (event) => AgentEventBus.instance.publish(event),
          );
          result = await coordinator.execute(
            command: args['command']?.toString() ?? '',
            timeoutSeconds: args['timeout_seconds'] is int ? args['timeout_seconds'] as int : 60,
          );
          break;
        default:
          throw FormatException('Unsupported tool: $name');
      }
      final ok = result['ok'] == true;
      final output = (result['output'] ?? result['path'] ?? result['error'] ?? result).toString();
      if (ok && (name == 'create_file' || name == 'slides_generator')) {
        final createdPath = name == 'slides_generator' ? args['path']?.toString() ?? path : path;
        _emitToolEvent('file_created', 'تم إنشاء الملف', toolName: name, path: createdPath,
            output: output, details: 'أنشأ المحرك الملف داخل مساحة العمل فعلياً.', stepId: toolStepId);
      } else if (ok && name == 'write_file') {
        _emitToolEvent('file_updated', 'تم تحديث الملف', toolName: name, path: path,
            output: output, details: 'حُفظت التغييرات في مساحة العمل فعلياً.', stepId: toolStepId);
      }
      if (name != 'gain_terminal') {
        _emitToolEvent(ok ? 'tool_output' : 'tool_error',
            ok ? _toolCompleteTitle(name) : 'فشل تنفيذ الأداة',
            toolName: name, path: path, output: output,
            details: ok ? null : result['error']?.toString(),
            status: ok ? 'completed' : 'failed', stepId: toolStepId);
      }
      return result;
    } catch (error) {
      if (name != 'gain_terminal') {
        _emitToolEvent('tool_error', 'فشل تنفيذ الأداة', toolName: name,
            path: path, output: error.toString(), status: 'failed', stepId: toolStepId);
      }
      rethrow;
    }
  }

  Future<void> _ensureBrowserSession() async {
    final request = requestBrowserSession;
    if (request == null) {
      throw StateError('The visible agent browser is unavailable in this execution context.');
    }
    await request();
    await BrowserSessionService.instance.waitUntilReady();
  }

  Future<Map<String, dynamic>> _spawnDynamicSubagent(
    String agentId, {
    bool Function()? isCancelled,
  }) async {
    final requestId = _activeRequestId;
    final child = _subagents.get(requestId, agentId);
    if (child == null) throw StateError('Subagent not found: $agentId');
    await _subagents.start(requestId, agentId);
    try {
      if (_cancelRequested || isCancelled?.call() == true) {
        throw const ToolCallInterrupted('dynamic_subagent');
      }
      final dependencies = child.dependsOn.map((dependencyId) {
        final dependency = _subagents.get(requestId, dependencyId)!;
        return 'نتيجة الوكيل السابق $dependencyId:\n${dependency.result ?? ''}';
      }).join('\n\n');
      final queuedMessages = _subagents.drainMessages(requestId, agentId)
          .map((item) => item['message']?.toString() ?? '')
          .where((message) => message.isNotEmpty)
          .join('\n');
      final goal = _subagents.currentGoal(requestId);
      final allowedTools = switch (child.agentType) {
        'explore' || 'plan' || 'reviewer' => const <String>{
            'read_file', 'list_files', 'web_search', 'fetch_urls', 'visit', 'click', 'input', 'find', 'scrollup', 'scrolldown',
            'browser_visit', 'browser_click', 'browser_find', 'browser_input', 'browser_state', 'browser_scroll_up', 'browser_scroll_down',
            'mcp_call', 'mcp_read_resource', 'send_message', 'wait_for_message',
          },
        'coder' => const <String>{
            'create_file', 'read_file', 'write_file', 'list_files', 'web_search',
            'execute_python', 'gain_terminal', 'mcp_call', 'mcp_read_resource',
            'send_message', 'wait_for_message',
          },
        _ => throw ArgumentError('Unknown subagent role: ${child.agentType}'),
      };
      final childConversationId = '$_activeConversationId::dynamic_subagent::$agentId';
      final childPrompt = '''
أنت وكيل فرعي مستقل من نوع ${child.agentType}.
الهدف الحالي:
${goal ?? 'الهدف الأصلي للطلب.'}
المهمة:
${child.prompt}
نتائج التبعيات:
${dependencies.isEmpty ? 'لا توجد تبعيات.' : dependencies}
رسائل واردة:
${queuedMessages.isEmpty ? 'لا توجد رسائل.' : queuedMessages}
قواعد:
- استخدم محرك النموذج والأدوات الحالية فقط؛ لا تنشئ وكيلاً فرعياً آخر.
- explore وplan وreviewer للقراءة والتحليل فقط؛ coder وحده يعدل الملفات.
- أوامر الطرفية تتطلب موافقة المستخدم كالمعتاد.
- افحص الحالة قبل تكرار أي أثر جانبي، ولا تدّع نجاحاً دون نتيجة أداة.
- أعد النتيجة والأدلة والملفات المتغيرة وما بقي غير منجز.
- لا تعرض التفكير الداخلي.
''';
      final context = await AgentMemoryService.instance.buildContext(
        childPrompt,
        conversationId: childConversationId,
      );
      final output = (await runZoned(
        () => _processInput(
          context.isEmpty ? childPrompt : '$context\n\nمهمة الوكيل: $childPrompt',
          allowedTools: allowedTools,
          shouldCancel: () => _cancelRequested || isCancelled?.call() == true,
        ),
        zoneValues: <Object, Object?>{
          _requestIdZoneKey: requestId,
          _parallelProviderZoneKey: Zone.current[_parallelProviderZoneKey] == true,
          _taskIdZoneKey: child.taskId,
          _agentTypeZoneKey: child.agentType,
          _conversationIdZoneKey: childConversationId,
        },
      )).trim();
      if (_cancelRequested || isCancelled?.call() == true ||
          output.startsWith('تم إيقاف') || output.contains('[تم إيقاف التوليد]')) {
        await _subagents.fail(requestId, agentId, 'تم إيقاف الوكيل الفرعي.', interrupted: true);
        return <String, dynamic>{'ok': false, 'status': 'interrupted', 'error': 'تم إيقاف الوكيل الفرعي.', 'subagent': child.toMap()};
      }
      if (output.isEmpty || output.startsWith('تعذر إكمال الطلب:') ||
          output.startsWith('وصل الوكيل إلى الحد الآمن')) {
        await _subagents.fail(requestId, agentId, output.isEmpty ? 'Empty subagent result.' : output);
        return <String, dynamic>{'ok': false, 'status': 'failed', 'error': output.isEmpty ? 'Empty subagent result.' : output, 'subagent': child.toMap()};
      }
      await _subagents.complete(requestId, agentId, output);
      return <String, dynamic>{'ok': true, 'status': 'completed', 'subagent': child.toMap()};
    } catch (error) {
      await _subagents.fail(requestId, agentId, error, interrupted: error is ToolCallInterrupted);
      return <String, dynamic>{'ok': false, 'status': child.status, 'error': error.toString(), 'subagent': child.toMap()};
    }
  }

  String _toolStartTitle(String name) {
    switch (name) {
      case 'create_file': return 'ينشئ ملفاً في مساحة العمل';
      case 'write_file': return 'يحدّث ملفاً موجوداً';
      case 'read_file': return 'يقرأ ملفاً من مساحة العمل';
      case 'execute_python': return 'يشغّل كود Python';
      case 'gain_terminal': return 'يطلب موافقة لتنفيذ أمر طرفية';
      case 'list_files': return 'يعرض ملفات مساحة العمل';
      case 'web_search': return 'يبحث على الويب';
      case 'todo_read': return 'يقرأ قائمة المهام';
      case 'todo_write': return 'يسجل مهمة محلية';
      case 'memory_space_insert': return 'يحفظ حقيقة في الذاكرة';
      case 'memory_space_update': return 'يحدث حقيقة في الذاكرة';
      case 'memory_space_delete': return 'يحذف حقيقة من الذاكرة';
      case 'memory_space_edits': return 'يراجع سجل تعديلات الذاكرة';
      case 'generate_speech': return 'يشغل القراءة الصوتية';
      case 'get_available_voices': return 'يستعرض أصوات الجهاز';
      case 'get_data_source': return 'يعرض مصادر MCP';
      case 'get_data_source_desc': return 'يفحص مصدر بيانات MCP';
      case 'generate_slides_outline': return 'ينشئ مخطط شرائح';
      case 'slides_generator': return 'ينشئ عرض شرائح HTML';
      case 'create_subagent': return 'يسجل وكيلاً فرعياً جديداً';
      case 'spawn_subagent': return 'يشغل وكيلاً فرعياً مسجلاً';
      case 'delete_subagent': return 'يخفي وكيلاً فرعياً من الإدارة';
      case 'check_subagent_status': return 'يفحص حالة وكيل فرعي';
      case 'send_message': return 'يرسل رسالة إلى وكيل فرعي';
      case 'wait_for_message': return 'ينتظر رسالة من صندوق الوارد';
      case 'ask_user': return 'يطلب توضيحاً من المستخدم';
      case 'update_goal': return 'يحدث هدف المهمة';
      default: return 'ينفّذ أداة';
    }
  }

  String _toolCompleteTitle(String name) {
    switch (name) {
      case 'create_file': return 'اكتمل إنشاء الملف';
      case 'write_file': return 'اكتمل تحديث الملف';
      case 'read_file': return 'اكتملت قراءة الملف';
      case 'execute_python': return 'اكتمل تنفيذ Python';
      case 'gain_terminal': return 'اكتمل تنفيذ أمر الطرفية';
      case 'list_files': return 'اكتمل استعراض الملفات';
      case 'web_search': return 'اكتمل البحث على الويب';
      case 'todo_read': return 'اكتملت قراءة المهام';
      case 'todo_write': return 'تم تسجيل المهمة المحلية';
      case 'memory_space_insert': return 'تم حفظ الحقيقة';
      case 'memory_space_update': return 'تم تحديث الحقيقة';
      case 'memory_space_delete': return 'تم حذف الحقيقة';
      case 'memory_space_edits': return 'اكتملت مراجعة سجل الذاكرة';
      case 'generate_speech': return 'اكتملت القراءة الصوتية';
      case 'get_available_voices': return 'اكتمل استعراض الأصوات';
      case 'get_data_source': return 'اكتمل استعراض مصادر MCP';
      case 'get_data_source_desc': return 'اكتمل فحص مصدر البيانات';
      case 'generate_slides_outline': return 'اكتمل مخطط الشرائح';
      case 'slides_generator': return 'اكتمل إنشاء عرض HTML';
      case 'create_subagent': return 'اكتمل تسجيل الوكيل الفرعي';
      case 'spawn_subagent': return 'اكتمل تشغيل الوكيل الفرعي';
      case 'delete_subagent': return 'اكتمل إخفاء الوكيل الفرعي';
      case 'check_subagent_status': return 'اكتمل فحص حالة الوكيل';
      case 'send_message': return 'أُرسلت الرسالة إلى الوكيل';
      case 'wait_for_message': return 'اكتمل انتظار الرسالة';
      case 'ask_user': return 'وصل رد المستخدم';
      case 'update_goal': return 'اكتمل تحديث هدف المهمة';
      default: return 'اكتمل تنفيذ الأداة';
    }
  }

  /// Serializes requests because llama.cpp owns one mutable native context.
  /// Concurrent calls can interleave prompts, cancellation and tool execution.
  Future<String> processInput(
    String input, {
    String conversationId = 'global',
    bool persistTurn = true,
    Set<String>? allowedTools,
    bool Function()? shouldCancel,
    String? requestId,
    String? taskId,
    String? agentType,
  }) async {
    final mode = await ModelProviderSettings.instance.getMode();
    final parallelProvider = mode == ModelProviderMode.openRouter;
    Future<String> executeScoped() async {
      if (shouldCancel?.call() == true) {
        return 'تم إيقاف تنفيذ الوكيل بناءً على طلب المستخدم.';
      }
      final context = await AgentMemoryService.instance.buildContext(
        input,
        conversationId: conversationId,
      );
      if (shouldCancel?.call() == true) {
        return 'تم إيقاف تنفيذ الوكيل بناءً على طلب المستخدم.';
      }
      final response = await _processInput(
        context.isEmpty ? input : '$context\n\nطلب المستخدم: $input',
        allowedTools: allowedTools,
        shouldCancel: shouldCancel,
      );
      if (persistTurn) {
        await AgentMemoryService.instance.saveTurn(
          input,
          response,
          conversationId: conversationId,
        );
      }
      return response;
    }

    final zoneValues = <Object, Object?>{
      _requestIdZoneKey: requestId ?? _fallbackRequestId,
      _parallelProviderZoneKey: parallelProvider,
      _taskIdZoneKey: taskId ?? '',
      _agentTypeZoneKey: agentType ?? '',
      _conversationIdZoneKey: conversationId,
    };
    if (parallelProvider) {
      _parallelExecutions++;
      try {
        return await runZoned(executeScoped, zoneValues: zoneValues);
      } finally {
        _parallelExecutions--;
      }
    }
    return _withRuntimeLock(
      () => runZoned(executeScoped, zoneValues: zoneValues),
    );
  }

  /// Multimodal image understanding through the currently selected vision
  /// provider. Local GGUF remains text-only; OpenRouter supplies vision.
  Future<String> processImage(
    File image, {
    String prompt = 'حلّل الصورة بصرياً بالتفصيل. صف العناصر الظاهرة والعلاقات بينها، واقرأ النصوص العربية واللاتينية إن وجدت. ميّز بين ما تراه فعلاً وما تستنتجه، ولا تخمّن التفاصيل غير الواضحة.',
  }) async {
    if (!await image.exists()) {
      throw FileSystemException('ملف الصورة غير موجود.', image.path);
    }
    final mode = await ModelProviderSettings.instance.getMode();
    switch (mode) {
      case ModelProviderMode.openRouter:
        return OpenAICompatibleProvider.instance.generateWithImage(image, prompt: prompt);
      case ModelProviderMode.local:
        throw StateError('النموذج المحلي الحالي نصّي فقط. استخدم OCR المحلي أو اختر نموذج رؤية عبر OpenRouter.');
    }
  }

  /// Produces a short structured planning response without invoking tools or
  /// persisting a user-visible conversation turn. It still uses the one shared
  /// inference lock and provider selected by the user.
  Future<String> generateStructuredOutput(
    String prompt, {
    String conversationId = 'global',
    bool Function()? shouldCancel,
  }) {
    return _withRuntimeLock(() async {
      if (shouldCancel?.call() == true) {
        return 'تم إيقاف التخطيط بناءً على طلب المستخدم.';
      }
      final context = await AgentMemoryService.instance.buildContext(
        prompt,
        conversationId: conversationId,
      );
      if (shouldCancel?.call() == true) {
        return 'تم إيقاف التخطيط بناءً على طلب المستخدم.';
      }
      final completePrompt = '''
أنت مخطط مهام لوكيل رئيسي. لا تنفذ أدوات ولا تكتب حلولاً نهائية.
حوّل هدف المستخدم إلى 2 إلى 6 مهام فرعية صغيرة قابلة للتحقق.
أعد JSON صالحاً فقط دون Markdown أو شرح، بهذا الشكل:
{"tasks":[{"id":"short_id","role":"explore|plan|coder|reviewer","title":"عنوان قصير","prompt":"تعليمات المهمة","depends_on":["short_id"]}]}
قواعد إلزامية:
- استخدم explore للاستكشاف والقراءة، plan للتصميم، coder للتعديلات البرمجية فقط، reviewer للتحقق.
- اجعل المهام المستقلة بلا تبعيات، واربط كل مهمة بما تحتاجه فعلاً من نتائج سابقة.
- لا تجعل أي وكيل ينشئ وكيلاً آخر.
- لا تضع أسراراً أو بيانات اعتماد في المهام.
- لا تدّع أن التنفيذ قد حدث؛ هذه خطة فقط.
- لا تستخدم coder إلا إذا كان هدف المستخدم يتطلب تعديل برنامج أو ملفات مشروع.
- اجعل prompt لكل مهمة مستقلاً بما يكفي، ولا يتجاوز 1200 حرفاً.
${context.isEmpty ? '' : 'سياق مختصر:\n$context\n'}
هدف المستخدم:
$prompt
''';
      late final String output;
      try {
        output = await _generateText(
          _boundPrompt(completePrompt),
          maxTokens: 1024,
          temperature: .1,
          shouldCancel: shouldCancel,
        );
      } catch (_) {
        if (_cancelRequested || shouldCancel?.call() == true) {
          return 'تم إيقاف التخطيط بناءً على طلب المستخدم.';
        }
        rethrow;
      }
      if (_cancelRequested || shouldCancel?.call() == true) {
        return 'تم إيقاف التخطيط بناءً على طلب المستخدم.';
      }
      return output.trim();
    });
  }

  /// Direct conversational path: no AgentKernel orchestration and no tool loop.
  /// The local GGUF model or the official OpenRouter provider answers normally.
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
    bool Function()? shouldCancel,
  }) async {
    final mode = await ModelProviderSettings.instance.getMode();
    switch (mode) {
      case ModelProviderMode.local:
        if (!await _llama.isLoaded()) {
          throw StateError('لم يتم تحميل نموذج GGUF المحلي. حمّل نموذجاً من قائمة النماذج أو اختر OpenRouter.');
        }
        return _llama.generate(prompt, maxTokens: maxTokens, temperature: temperature);
      case ModelProviderMode.openRouter:
        return OpenAICompatibleProvider.instance.generateStreaming(
          prompt,
          maxTokens: maxTokens,
          temperature: temperature,
          isCancelled: () => _cancelRequested || shouldCancel?.call() == true,
          onDelta: (delta) {
            AgentEventBus.instance.publish(<String, dynamic>{
              'id': 'stream_${_activeRequestId}_${DateTime.now().microsecondsSinceEpoch}',
              'request_id': _activeRequestId,
              'attempt_id': _activeRequestId,
              'task_id': _activeTaskId,
              'agent_type': _activeAgentType,
              'type': 'stream_token',
              'content': delta,
              'status': 'streaming',
              'timestamp': DateTime.now().toUtc().toIso8601String(),
            });
          },
        );
    }
  }

  Future<String> _processInput(
    String input, {
    Set<String>? allowedTools,
    bool Function()? shouldCancel,
  }) async {
    if (shouldCancel?.call() == true) {
      return 'تم إيقاف تنفيذ الوكيل بناءً على طلب المستخدم.';
    }
    final parallelProvider = Zone.current[_parallelProviderZoneKey] == true;
    bool isCancelled() => shouldCancel?.call() == true || _cancelRequested;
    if (!parallelProvider) _cancelRequested = false;
    input = _boundPrompt(input);
    if (await ModelProviderSettings.instance.getMode() == ModelProviderMode.local && !await _llama.isLoaded()) {
      return '⚠️ لم يتم تحميل نموذج GGUF المحلي. حمّل نموذج GGUF أو اختر OpenRouter من إعدادات المزوّد.';
    }
    final baseToolCatalog = allowedTools == null
        ? ToolManager().promptCatalog
        : ToolManager().promptCatalogFor(allowedTools);
    final remoteToolCatalog = allowedTools != null && !allowedTools.contains('mcp_call')
        ? ''
        : await McpClient.instance.promptCatalog(isCancelled: isCancelled);
    final toolCatalog = '$baseToolCatalog\n$remoteToolCatalog';
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
        if (isCancelled()) return 'تم إيقاف تنفيذ الوكيل بناءً على طلب المستخدم.';

        Map<String, dynamic> payload;
        if (pendingReflexionPayload != null) {
          payload = pendingReflexionPayload;
          pendingReflexionPayload = null;
        } else {
          final generated = await _generateText(
            history.toString(),
            maxTokens: 768,
            temperature: .25,
            shouldCancel: isCancelled,
          );
          if (isCancelled()) {
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
        if (!ToolManager().supports(toolName) ||
            (allowedTools != null && !allowedTools.contains(toolName)) ||
            rawArgs is! Map<String, dynamic>) {
          history
            ..write('\n\nSystem Note: Unsupported tool or invalid arguments. Use only the registered tool catalogue.\n\nAssistant:');
          continue;
        }

        final signature = jsonEncode(<String, dynamic>{
          'name': toolName,
          'arguments': rawArgs,
        });
        if (!executedCalls.add(signature)) {
          _emitToolEvent(
            'reflexion_failed',
            'أوقف الوكيل محاولة تكرار الإجراء نفسه',
            toolName: toolName,
            details: 'The proposed recovery action duplicates an action already attempted.',
            status: 'failed',
          );
          return 'تعذر إكمال الطلب: لم يتحقق الهدف؛ اقترح محرك التأمل إجراءً مكرراً، فأوقفته آلية منع التكرار.';
        }

        final toolStepId = 'verified_step_${_activeRequestId}_${DateTime.now().microsecondsSinceEpoch}';
        final toolCallId = 'call_${_activeRequestId}_${DateTime.now().microsecondsSinceEpoch}_${++_toolEventSequence}';
        final toolCall = _toolCalls.begin(
          toolCallId: toolCallId,
          requestId: _activeRequestId,
          toolName: toolName,
        );
        late Map<String, dynamic> result;
        late bool verificationPassed;
        late String verificationMessage;
        _emitToolEvent(
          'tool_call_started',
          'بدأ استدعاء الأداة',
          toolName: toolName,
          status: 'running',
          stepId: toolStepId,
          toolCallId: toolCallId,
        );
        try {
          await _withToolLock(() async {
          try {
            toolCall.throwIfCancelled();
            result = await _executeToolUnlocked(
              payload,
              stepId: toolStepId,
              allowedTools: allowedTools,
              isCancelled: () => toolCall.isCancelled || isCancelled(),
            );
          } catch (error) {
            result = <String, dynamic>{'ok': false, 'error': error.toString()};
          }
          if (toolCall.isCancelled) {
            verificationPassed = false;
            verificationMessage = 'تمت مقاطعة استدعاء الأداة المحدد.';
            return;
          }
          if (isCancelled()) {
            verificationPassed = false;
            verificationMessage = 'تم الإيقاف بعد تنفيذ الأداة وقبل التحقق.';
            return;
          }
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
          verificationPassed = verification.passed;
          verificationMessage = verification.message;
          _emitToolEvent(
            verification.passed ? 'verification_passed' : 'verification_failed',
            verification.passed ? 'اجتاز التحقق المستقل' : 'فشل التحقق المستقل',
            toolName: toolName,
            output: jsonEncode(verification.evidence ?? const <String, Object?>{}),
            details: verification.message,
            status: verification.passed ? 'completed' : 'failed',
            stepId: toolStepId,
            toolCallId: toolCallId,
          );
          });
          if (toolCall.isCancelled) {
            _emitToolEvent(
              'tool_call_interrupted',
              'تمت مقاطعة استدعاء الأداة',
              toolName: toolName,
              details: 'أُوقف هذا الاستدعاء بمعرّفه المستقل دون إيقاف الطلبات الأخرى.',
              status: 'interrupted',
              stepId: toolStepId,
              toolCallId: toolCallId,
            );
            return 'تم إيقاف استدعاء الأداة المحدد.';
          }
          if (isCancelled()) return 'تم إيقاف الوكيل بعد اكتمال الأداة الحالية.';
          _emitToolEvent(
            'tool_call_completed',
            'اكتمل استدعاء الأداة',
            toolName: toolName,
            status: 'completed',
            stepId: toolStepId,
            toolCallId: toolCallId,
          );
        } finally {
          _toolCalls.finish(toolCallId);
        }

        if (!verificationPassed) {
          final failedAction = jsonEncode(payload);
          history
            ..write('\n\nSystem Note: Tool $toolName result: ${jsonEncode(result)}')
            ..write('\nIndependent verification FAILED: $verificationMessage')
            ..write('\nDo not claim the goal is complete. Choose a different corrective tool action.\n\nAssistant:');

          if (reflexionAttempts >= maxReflexionAttempts) {
            return 'تعذر إكمال الطلب: لم يتحقق الهدف بعد $maxReflexionAttempts محاولات تصحيح آمنة. آخر نتيجة: $verificationMessage';
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
              errorMessage: verificationMessage,
              shouldCancel: isCancelled,
            );
            final proposed = <String, dynamic>{
              'name': action.toolName,
              'arguments': action.arguments,
            };
            final normalizedProposedSignature = jsonEncode(<String, dynamic>{
              'name': action.toolName,
              'arguments': action.arguments,
            });
            if (normalizedProposedSignature == signature || executedCalls.contains(normalizedProposedSignature)) {
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
            if (isCancelled()) return 'تم إيقاف التوليد بناءً على طلب المستخدم.';
            _emitToolEvent(
              'reflexion_failed',
              'تعذر توليد إجراء تصحيحي آمن',
              toolName: toolName,
              details: error.toString(),
              status: 'failed',
              stepId: toolStepId,
            );
            return 'تعذر إكمال الطلب: فشل التحقق من النتيجة، ولم يتمكن محرك التأمل من اقتراح إجراء بديل صالح: $error';
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
      if (_cancelRequested || shouldCancel?.call() == true) {
        _emitToolEvent(
          'generation_interrupted',
          'تم إيقاف التوليد',
          details: 'تم إيقاف تدفق المزوّد بناءً على طلب المستخدم.',
          status: 'interrupted',
        );
        return 'تم إيقاف التوليد بناءً على طلب المستخدم.';
      }
      return 'تعذر إكمال الطلب: $e';
    }
  }
}
