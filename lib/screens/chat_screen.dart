import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/agent_activity_indicators.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import '../services/model_service.dart';
import '../services/agent_service.dart';
import '../services/file_upload_service.dart';
import '../services/agent_memory_service.dart';
import '../services/image_recognition_service.dart';
import 'agent_workspace_screen.dart';
import 'agent_workflow_screen.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_screen.dart';
import '../models/chat_session.dart';
import 'dart:convert';
import 'package:speech_to_text/speech_to_text.dart';
import '../services/openrouter_service.dart';
import '../services/github_repository_service.dart';
import '../services/cloud_storage_service.dart';
import '../services/web_search_service.dart';
import '../agent/task_manager.dart';
import '../theme/giant_palette.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  final ScrollController _scrollController = ScrollController();
  final ModelService _modelService = ModelService();
  
  bool _isLoading = false;
  String _thinkingStage = '';
  static const EventChannel _agentEvents = EventChannel('giant_agent_stream');
  static const MethodChannel _fileReceiver = MethodChannel('file_receiver');
  StreamSubscription<dynamic>? _agentEventSubscription;
  StreamSubscription<dynamic>? _kernelEventSubscription;
  final List<Map<String, dynamic>> _agentSteps = [];
  String _activeAgentRequestId = '';
  final Set<String> _collapsedTimelineIds = <String>{};
  String _streamingResponse = '';
  int _streamingShimmerStart = 0;
  String _toolStreamBuffer = '';
  bool _insideToolCall = false;
  final Set<String> _seenStreamTokenEventIds = <String>{};
  static const String _toolCallOpen = '<tool_call>';
  static const String _toolCallClose = '</tool_call>';
  final Terminal _terminal = Terminal(maxLines: 5000);
  bool _terminalHasActivity = false;
  final SpeechToText _speech = SpeechToText();
  bool _isListening = false;
  bool _webSearchEnabled = false;
  bool _includeGithubContext = false;
  bool _openRouterEnabled = false;
  bool _agentModeEnabled = true;

  // Keep tool-call JSON out of the user-facing answer stream. The actual
  // invocation and result are represented by structured native tool events.
  String _visibleAnswerDelta(String chunk) {
    _toolStreamBuffer += chunk;
    final visible = StringBuffer();
    while (_toolStreamBuffer.isNotEmpty) {
      if (_insideToolCall) {
        final end = _toolStreamBuffer.indexOf(_toolCallClose);
        if (end >= 0) {
          _toolStreamBuffer = _toolStreamBuffer.substring(end + _toolCallClose.length);
          _insideToolCall = false;
          continue;
        }
        final keep = _toolCallClose.length - 1;
        if (_toolStreamBuffer.length > keep) {
          _toolStreamBuffer = _toolStreamBuffer.substring(_toolStreamBuffer.length - keep);
        }
        break;
      }
      final start = _toolStreamBuffer.indexOf(_toolCallOpen);
      if (start >= 0) {
        visible.write(_toolStreamBuffer.substring(0, start));
        _toolStreamBuffer = _toolStreamBuffer.substring(start + _toolCallOpen.length);
        _insideToolCall = true;
        continue;
      }
      final keep = _toolCallOpen.length - 1;
      final safeLength = _toolStreamBuffer.length - keep;
      if (safeLength > 0) {
        visible.write(_toolStreamBuffer.substring(0, safeLength));
        _toolStreamBuffer = _toolStreamBuffer.substring(safeLength);
      }
      break;
    }
    return visible.toString();
  }

  String _flushVisibleAnswerBuffer() {
    if (_insideToolCall) {
      _toolStreamBuffer = '';
      return '';
    }
    final remaining = _toolStreamBuffer;
    _toolStreamBuffer = '';
    return remaining;
  }

  void _handleAgentEvent(dynamic event) {
    if (!mounted || event is! Map) return;
    final step = Map<String, dynamic>.from(event);
    if (step['type'] == 'shared_file') {
      final path = step['path']?.toString();
      if (path != null && path.isNotEmpty) _processSharedFilePath(path);
      return;
    }
    if (step['tool_name'] == 'execute_python') {
      _terminalHasActivity = true;
      final type = step['type']?.toString();
      if (type == 'tool_start') {
        _terminal.write('\r\n\x1B[33m>>> Python execution started\x1B[0m\r\n');
        final code = step['content']?.toString() ?? '';
        if (code.isNotEmpty) _terminal.write('\x1B[90m$code\x1B[0m\r\n');
      } else if (type == 'tool_output') {
        final output = step['output']?.toString() ?? '';
        if (output.isNotEmpty) _terminal.write('$output\r\n');
        _terminal.write('\x1B[32m[completed]\x1B[0m\r\n');
      } else if (type == 'tool_error') {
        _terminal.write('\x1B[31m${step['output']?.toString() ?? step['details']?.toString() ?? 'Python failed'}\x1B[0m\r\n');
      }
    }
    if (step['type'] == 'stream_token') {
      // Native token callbacks are deltas. Ignore a replayed event id so a
      // reconnect/re-delivery cannot append the same chunk twice.
      final tokenEventId = step['id']?.toString() ?? '';
      if (tokenEventId.isNotEmpty && !_seenStreamTokenEventIds.add(tokenEventId)) return;
      if (_seenStreamTokenEventIds.length > 4096) {
        _seenStreamTokenEventIds.remove(_seenStreamTokenEventIds.first);
      }
      final token = step['text']?.toString() ?? '';
      final visible = _visibleAnswerDelta(token);
      if (visible.isNotEmpty) setState(() {
        _streamingShimmerStart = _streamingResponse.length;
        _streamingResponse += visible;
      });
      _scrollToBottom();
      return;
    }
    step.putIfAbsent('session_id', () => _currentSessionId);
    if (_activeAgentRequestId.isNotEmpty) {
      step.putIfAbsent('request_id', () => _activeAgentRequestId);

      // Collapse all repeated native inference-start/update events into one
      // stable timeline record for this user request. Later events update it.
      final nativeTitle = step['title']?.toString() ?? '';
      if (step['type'] == 'agent_status' &&
          (nativeTitle.contains('استدلال النموذج المحلي') ||
           nativeTitle.contains('توليد الإجابة') ||
           nativeTitle.contains('توقف التوليد') ||
           nativeTitle.contains('الاستدلال المحلي'))) {
        step['id'] = 'native_inference_$_activeAgentRequestId';
        step['request_id'] = _activeAgentRequestId;
      } else if (step['type'] == 'task_finished') {
        step['id'] = 'native_finished_$_activeAgentRequestId';
        step['request_id'] = _activeAgentRequestId;
      }
    }
    final eventType = step['type']?.toString();
    if (eventType == 'file_created' || eventType == 'file_updated') {
      final path = step['file_name']?.toString();
      if (path != null && path.isNotEmpty) {
        AgentWorkspaceScreen.fileChanges.value = path;
      }
    }
    final id = step['id']?.toString() ?? '';
    if (id.isEmpty) return;
    _saveAgentEvent(step);
    setState(() {
      final index = _agentSteps.indexWhere((item) => item['id'] == id);
      if (index >= 0) { _agentSteps[index] = step; } else { _agentSteps.add(step); }
      _thinkingStage = step['title']?.toString() ?? '';
    });
    AgentWorkflowScreen.publish(_agentSteps, finalOutputText: _latestAssistantOutput);
    _scrollToBottom();
  }

  Future<String> _generateWithStages(String prompt) async {
    _toolStreamBuffer = '';
    _insideToolCall = false;
    if (mounted) setState(() {
      _streamingResponse = '';
      _streamingShimmerStart = 0;
      _thinkingStage = 'بانتظار أحداث المحرك المحلي...';
    });
    try {
      return await AgentService.instance.runTask(prompt, conversationId: _currentSessionId);
    } finally {
      final tail = _flushVisibleAnswerBuffer();
      if (mounted) setState(() {
        if (tail.isNotEmpty) {
          _streamingShimmerStart = _streamingResponse.length;
          _streamingResponse += tail;
        }
        _thinkingStage = '';
      });
    }
  }
  TextDirection _contentDirection(String value) {
    for (final rune in value.runes) {
      // Resolve direction from the first strong character, not punctuation,
      // whitespace, or digits. Flutter's bidi algorithm then handles mixed text.
      if ((rune >= 0x0600 && rune <= 0x06FF) ||
          (rune >= 0x0750 && rune <= 0x077F) ||
          (rune >= 0x08A0 && rune <= 0x08FF) ||
          (rune >= 0xFB50 && rune <= 0xFDFF) ||
          (rune >= 0xFE70 && rune <= 0xFEFF)) {
        return TextDirection.rtl;
      }
      if ((rune >= 0x0041 && rune <= 0x005A) ||
          (rune >= 0x0061 && rune <= 0x007A) ||
          (rune >= 0x00C0 && rune <= 0x02AF)) {
        return TextDirection.ltr;
      }
    }
    return TextDirection.rtl;
  }

  bool _isLiveInferenceStatus(Map<String, dynamic> event) {
    if (event['type'] != 'agent_status' || event['status'] != 'running') {
      return false;
    }
    final title = event['title']?.toString() ?? '';
    return title.contains('استدلال النموذج المحلي') ||
        title.contains('توليد الإجابة') ||
        title.contains('الاستدلال المحلي');
  }

  bool _isInterruptedTaskOutput(String output) =>
      TaskManager.classifyResult(output) == TaskExecutionOutcome.interrupted;

  bool _isFailedTaskOutput(String output) =>
      TaskManager.classifyResult(output) == TaskExecutionOutcome.failed;

  Future<String> _runTrackedTask(
    String prompt, {
    String? taskId,
    String? description,
  }) async {
    final manager = TaskManager();
    final tracked = taskId == null
        ? await manager.createTask(
            description ?? prompt,
            conversationId: _currentSessionId,
          )
        : null;
    final activeTaskId = taskId ?? tracked!['id'].toString();
    await manager.markRunning(activeTaskId);
    try {
      final output = await _generateWithStages(prompt);
      if (_isInterruptedTaskOutput(output)) {
        await manager.markInterrupted(
          activeTaskId,
          'توقف التنفيذ قبل اكتمال المهمة؛ يمكن استئنافها من سياق الجلسة.',
        );
      } else if (_isFailedTaskOutput(output)) {
        await manager.markFailed(activeTaskId, output);
      } else {
        await manager.markCompleted(activeTaskId, output);
      }
      return output;
    } catch (error) {
      await manager.markFailed(activeTaskId, error.toString());
      rethrow;
    }
  }

  List<Map<String, dynamic>> _models = [];
  Map<String, dynamic> _activeModel = {};
  Database? _db;
  String _currentSessionId = '';
  List<ChatSession> _sessions = [];
  bool _sessionReady = false;
  Future<void> _sharedFileQueue = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _initDatabase();
    _kernelEventSubscription = AgentService.instance.events.listen(
      (event) => _handleAgentEvent(event.toMap()),
      onError: (Object error) {
        if (!mounted) return;
        _handleAgentEvent({
          'id': 'kernel_stream_error_${DateTime.now().microsecondsSinceEpoch}',
          'type': 'orchestration_error',
          'title': 'تعذر استقبال أحداث التنسيق',
          'status': 'failed',
          'details': error.toString(),
        });
      },
    );
    _agentEventSubscription = _agentEvents.receiveBroadcastStream().listen(
      _handleAgentEvent,
      onError: (Object error) {
        if (!mounted) return;
        setState(() { _agentSteps.add({'id': 'stream_error_${DateTime.now().millisecondsSinceEpoch}', 'title': 'تعذر استقبال أحداث الوكيل', 'status': 'failed', 'details': error.toString()}); });
      },
    );
  }

  Future<void> _initDatabase() async {
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      '${dir.path}/conversations.db',
      version: 4,
      onCreate: (db, version) async {
        await db.execute('''CREATE TABLE sessions (
          id TEXT PRIMARY KEY, title TEXT NOT NULL,
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
        )''');
        await db.execute('''CREATE TABLE messages (
          id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL,
          content TEXT, isUser INTEGER, timestamp INTEGER, request_id TEXT
        )''');
        await db.execute('''CREATE TABLE agent_events (
          id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL,
          event_key TEXT NOT NULL, event_json TEXT NOT NULL, timestamp INTEGER NOT NULL,
          UNIQUE(session_id, event_key)
        )''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''CREATE TABLE sessions (
            id TEXT PRIMARY KEY, title TEXT NOT NULL,
            created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
          )''');
          await db.execute('ALTER TABLE messages ADD COLUMN session_id TEXT');
          final now = DateTime.now().millisecondsSinceEpoch;
          await db.insert('sessions', {'id':'legacy-session','title':'المحادثة السابقة','created_at':now,'updated_at':now});
          await db.update('messages', {'session_id':'legacy-session'});
          await db.execute('''CREATE TABLE agent_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL,
            event_json TEXT NOT NULL, timestamp INTEGER NOT NULL
          )''');
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE agent_events ADD COLUMN event_key TEXT');
          final oldEvents = await db.query('agent_events');
          for (final row in oldEvents) {
            await db.update('agent_events', {'event_key': 'legacy_${row['id']}'}, where: 'id = ?', whereArgs: [row['id']]);
          }
          await db.execute('CREATE UNIQUE INDEX agent_events_session_key ON agent_events(session_id, event_key)');
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE messages ADD COLUMN request_id TEXT');
        }
      },
    );
    final modePrefs = await SharedPreferences.getInstance();
    _agentModeEnabled = modePrefs.getBool('giant_agent_mode_enabled') ?? true;
    await _ensureCurrentSession();
    await _loadSessions();
    await _loadHistory();
    await _init();
    await _resumePendingTask();
    await _consumeInitialSharedFile();
  }

  Future<void> _consumeInitialSharedFile() async {
    try {
      final path = await _fileReceiver.invokeMethod<String>('getSharedFile');
      if (path != null && path.isNotEmpty && mounted) {
        await _processSharedFilePath(path);
      }
    } on PlatformException catch (error) {
      debugPrint('Unable to receive initial shared file: ${error.message}');
    } on MissingPluginException {
      // The native share bridge is Android-only.
    }
  }

  Future<void> _processSharedFilePath(String path) {
    _sharedFileQueue = _sharedFileQueue.then((_) async {
      // Do not drop an incoming Android share while a response is generating.
      while (_isLoading && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      final file = File(path);
      try {
        if (mounted) await _processFile(file);
      } finally {
        // Native content:// shares are copied into this private cache folder.
        // Remove the temporary copy after analysis, including on failures.
        if (file.parent.path.endsWith('${Platform.pathSeparator}shared_files')) {
          try {
            if (await file.exists()) await file.delete();
          } catch (error) {
            debugPrint('Unable to remove temporary shared file: $error');
          }
        }
      }
    });
    return _sharedFileQueue;
  }

  String _newSessionId() => DateTime.now().microsecondsSinceEpoch.toString();

  Future<void> _ensureCurrentSession() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('giant_active_session_id');
    final rows = await _db!.query('sessions', where: 'id = ?', whereArgs: [saved]);
    if (rows.isNotEmpty) {
      _currentSessionId = saved!;
    } else {
      final now = DateTime.now();
      _currentSessionId = _newSessionId();
      await _db!.insert('sessions', {
        'id': _currentSessionId, 'title': 'جلسة جديدة',
        'created_at': now.millisecondsSinceEpoch, 'updated_at': now.millisecondsSinceEpoch,
      });
      await prefs.setString('giant_active_session_id', _currentSessionId);
    }
    _sessionReady = true;
  }

  Future<void> _loadSessions() async {
    final rows = await _db?.query('sessions', orderBy: 'updated_at DESC');
    if (!mounted || rows == null) return;
    setState(() => _sessions = rows.map((row) => ChatSession.fromMap(row)).toList());
  }

  String get _latestAssistantOutput {
    for (final message in _messages.reversed) {
      if (message['isUser'] != true) return message['content']?.toString() ?? '';
    }
    return '';
  }

  Future<void> _loadHistory() async {
    final messages = await _db?.query('messages', where: 'session_id = ?', whereArgs: [_currentSessionId], orderBy: 'timestamp ASC');
    final events = await _db?.query('agent_events', where: 'session_id = ?', whereArgs: [_currentSessionId], orderBy: 'timestamp ASC');
    if (!mounted) return;
    final restoredMessages = (messages ?? []).map((msg) => {
      'dbId': msg['id'],
      'isUser': msg['isUser'] == 1,
      'content': msg['content'] as String,
      'time': DateTime.fromMillisecondsSinceEpoch(msg['timestamp'] as int),
      'requestId': msg['request_id']?.toString() ?? '',
    }).toList();
    for (final message in restoredMessages) {
      if (message['isUser'] == true && (message['requestId']?.toString() ?? '').isEmpty) {
        message['requestId'] = 'legacy_${(message['time'] as DateTime).microsecondsSinceEpoch}';
      }
    }
    final restoredEvents = <Map<String, dynamic>>[];
    for (final row in events ?? []) {
      final event = Map<String, dynamic>.from(jsonDecode(row['event_json'] as String) as Map);
      if ((event['request_id']?.toString() ?? '').isEmpty) {
        final eventTime = row['timestamp'] as int;
        for (final message in restoredMessages.reversed) {
          final time = (message['time'] as DateTime).millisecondsSinceEpoch;
          if (message['isUser'] == true && time <= eventTime) {
            final legacyRequestId = message['requestId']?.toString() ?? '';
            if (legacyRequestId.isNotEmpty) event['request_id'] = legacyRequestId;
            break;
          }
        }
      }
      restoredEvents.add(event);
    }
    setState(() {
      _messages..clear()..addAll(restoredMessages);
      _agentSteps..clear()..addAll(restoredEvents);
    });
    AgentWorkflowScreen.publish(_agentSteps, finalOutputText: _latestAssistantOutput);
    _scrollToBottom();
  }

  Future<void> _saveAgentEvent(Map<String, dynamic> event) async {
    if (!_sessionReady || _db == null || event['type'] == 'stream_token') return;
    final eventKey = event['id']?.toString();
    if (eventKey == null || eventKey.isEmpty) return;
    final existing = await _db!.query('agent_events',
      columns: ['id'], where: 'session_id = ? AND event_key = ?',
      whereArgs: [_currentSessionId, eventKey], limit: 1);
    final values = {
      'session_id': _currentSessionId,
      'event_key': eventKey,
      'event_json': jsonEncode(event),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    if (existing.isEmpty) {
      await _db!.insert('agent_events', values);
    } else {
      await _db!.update('agent_events', values, where: 'id = ?', whereArgs: [existing.first['id']]);
    }
  }

  Future<void> _pruneOldSessions() async {
    final old = await _db?.query('sessions', columns: ['id'], orderBy: 'updated_at DESC', limit: 1000, offset: 50);
    if (old == null || old.isEmpty) return;
    for (final row in old) {
      final id = row['id'] as String;
      if (id == _currentSessionId) continue;
      await _db?.delete('messages', where: 'session_id = ?', whereArgs: [id]);
      await _db?.delete('agent_events', where: 'session_id = ?', whereArgs: [id]);
      await _db?.delete('sessions', where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<void> _createNewSession() async {
    if (_isLoading) return;
    final now = DateTime.now();
    final id = _newSessionId();
    await _db?.insert('sessions', {
      'id': id, 'title': 'جلسة جديدة',
      'created_at': now.millisecondsSinceEpoch, 'updated_at': now.millisecondsSinceEpoch,
    });
    _currentSessionId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('giant_active_session_id', id);
    await _pruneOldSessions();
    if (!mounted) return;
    setState(() { _messages.clear(); _agentSteps.clear(); _streamingResponse = ''; });
    AgentWorkflowScreen.publish(_agentSteps, finalOutputText: _latestAssistantOutput);
    await _loadSessions();
    _scrollToBottom();
  }

  Future<void> _switchSession(ChatSession session) async {
    if (_isLoading || session.id == _currentSessionId) return;
    _currentSessionId = session.id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('giant_active_session_id', session.id);
    if (mounted) Navigator.pop(context);
    await _loadHistory();
  }

  Future<void> _deleteSession(ChatSession session) async {
    if (_isLoading) return;
    await _db?.delete('messages', where: 'session_id = ?', whereArgs: [session.id]);
    await _db?.delete('agent_events', where: 'session_id = ?', whereArgs: [session.id]);
    await AgentMemoryService.instance.deleteConversationMemory(session.id);
    await _db?.delete('sessions', where: 'id = ?', whereArgs: [session.id]);
    if (session.id == _currentSessionId) {
      final remaining = await _db?.query('sessions', orderBy: 'updated_at DESC', limit: 1);
      if (remaining == null || remaining.isEmpty) {
        await _createNewSession();
      } else {
        final next = ChatSession.fromMap(remaining.first);
        _currentSessionId = next.id;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('giant_active_session_id', next.id);
        await _loadHistory();
      }
    }
    await _loadSessions();
  }

  Future<void> _saveMessage(String content, bool isUser, {String? requestId}) async {
    if (!_sessionReady || _currentSessionId.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final insertedId = await _db?.insert('messages', {
      'session_id': _currentSessionId,
      'content': content,
      'isUser': isUser ? 1 : 0,
      'timestamp': now,
      'request_id': requestId,
    });
    if (insertedId != null) {
      for (final message in _messages.reversed) {
        if (message['dbId'] == null && message['isUser'] == isUser &&
            message['content']?.toString() == content) {
          message['dbId'] = insertedId;
          break;
        }
      }
    }
    await _db?.update('sessions', {'updated_at': now},
      where: 'id = ?', whereArgs: [_currentSessionId]);
    await _loadSessions();
    if (!isUser) {
      AgentWorkflowScreen.publish(_agentSteps, finalOutputText: _latestAssistantOutput);
    }
  }

  Future<void> _clearAllSessions() async {
    if (_isLoading) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مسح جميع الجلسات'),
        content: const Text('سيتم حذف سجل المحادثات والأحداث المحفوظة. لن تُحذف ملفات مساحة العمل.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('مسح الكل', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    await _db?.delete('messages');
    await _db?.delete('agent_events');
    await AgentMemoryService.instance.clearConversationMemory();
    await _db?.delete('sessions');
    await _createNewSession();
  }

  Future<void> _clearHistory() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مسح المحادثات'),
        content: const Text('هل أنت متأكد؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(
            onPressed: () async {
              await _db?.delete('messages', where: 'session_id = ?', whereArgs: [_currentSessionId]);
              await _db?.delete('agent_events', where: 'session_id = ?', whereArgs: [_currentSessionId]);
              await AgentMemoryService.instance.deleteConversationMemory(_currentSessionId);
              setState(() { _messages.clear(); _agentSteps.clear(); });
              AgentWorkflowScreen.publish(_agentSteps, finalOutputText: _latestAssistantOutput);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم مسح المحادثات')),
              );
            },
            child: const Text('مسح', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showTerminal({Map<String, dynamic>? step}) {
    if (step == null && !_terminalHasActivity) {
      _terminal.write('\x1B[2J\x1B[H');
      _terminal.write('\x1B[32mroot@giant-agent\x1B[0m:\x1B[34m~\x1B[0m# Waiting for commands...\r\n');
    }
    if (step != null) {
      _terminal.write('\x1B[2J\x1B[H');
      final title = step['title']?.toString() ?? 'Agent execution';
      final tool = step['tool_name']?.toString() ?? '';
      final code = step['content']?.toString() ?? '';
      final output = step['output']?.toString() ?? step['details']?.toString() ?? '';
      _terminal.write('\x1B[36m$title\x1B[0m\r\n');
      if (tool.isNotEmpty) _terminal.write('\x1B[90mTool: $tool\x1B[0m\r\n');
      if (code.isNotEmpty) _terminal.write('\x1B[33m>>>\x1B[0m\r\n$code\r\n');
      if (output.isNotEmpty) _terminal.write('$output\r\n');
      final status = step['status']?.toString() ?? 'unknown';
      _terminal.write(status == 'failed'
          ? '\x1B[31m[failed]\x1B[0m\r\n'
          : status == 'completed'
              ? '\x1B[32m[completed]\x1B[0m\r\n'
              : '\x1B[33m[$status]\x1B[0m\r\n');
    }

    // A dedicated route keeps terminal output separate from the chat composer
    // and conversation instead of covering them with a modal overlay.
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (terminalContext) => Scaffold(
        backgroundColor: const Color(0xFF050A0F),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  const Icon(Icons.terminal, color: Colors.greenAccent),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    step == null ? 'Agent Terminal' : (step['title']?.toString() ?? 'نتيجة التنفيذ'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  )),
                  IconButton(
                    onPressed: () {
                      _terminal.write('\x1B[2J\x1B[H');
                      _terminalHasActivity = false;
                      _terminal.write('\x1B[32mroot@giant-agent\x1B[0m:\x1B[34m~\x1B[0m# Waiting for commands...\r\n');
                    },
                    icon: const Icon(Icons.delete_sweep, color: Colors.white70),
                  ),
                  IconButton(onPressed: () => Navigator.pop(terminalContext), icon: const Icon(Icons.close, color: Colors.white70)),
                ]),
              ),
              const Divider(height: 1, color: Colors.white24),
              Expanded(child: TerminalView(_terminal, readOnly: true)),
            ],
          ),
        ),
      ),
    ));
  }

  Future<void> _init() async {
    await AgentService.instance.initialize();
    final remoteEnabled = await OpenRouterService.instance.isEnabled();
    if (!mounted) return;
    setState(() {
      _models = _modelService.getModels();
      _activeModel = _modelService.getActiveModel();
      _openRouterEnabled = remoteEnabled;
    });
  }

  Future<void> _refreshModels() async {
    await _modelService.refreshModels();
    if (!mounted) return;
    setState(() {
      _models = _modelService.getModels();
      _activeModel = _modelService.getActiveModel();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تحديث النماذج')),
    );
  }

  Future<void> _importModel() async {
    bool success = false;
    try { success = await _modelService.importModelFromFile(); }
    catch (_) { success = false; }
    if (success && mounted) {
      await _refreshModels();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم استيراد النموذج بنجاح')),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فشل استيراد النموذج')),
      );
    }
  }

  Future<void> _cancelAgent() async {
    try {
      final stopped = _agentModeEnabled
          ? await AgentService.instance.cancel()
          : await _modelService.cancelGeneration();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(stopped
            ? 'تم إرسال طلب الإيقاف؛ ستُسجّل المهمة بأنها أوقفت بواسطة المستخدم.'
            : 'سيتوقف الوكيل بعد الأداة الحالية، وستُسجّل المهمة بأنها أوقفت بواسطة المستخدم.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر إيقاف التوليد: $e')),
      );
    }
  }

  Future<void> _exportWorkspace() async {
    try {
      final exported = await _modelService.exportWorkspace();
      final path = exported['path']?.toString();
      if (path == null || path.isEmpty) throw Exception('لم يتم إنشاء ملف ZIP.');
      await Share.shareXFiles(
        [XFile(path, mimeType: 'application/zip')],
        text: 'مشروع مساحة عمل Giant Agent',
        subject: 'Giant Agent Workspace',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل تصدير مساحة العمل: $e')),
      );
    }
  }

  String _contextualPrompt(String currentPrompt) {
    final prior = _messages.length > 1 ? _messages.sublist(0, _messages.length - 1) : <Map<String, dynamic>>[];
    final recent = prior.length > 5 ? prior.sublist(prior.length - 5) : prior;
    if (recent.isEmpty) return currentPrompt;
    final buffer = StringBuffer('سياق الجلسة الحالية فقط (آخر خمس رسائل، الأقدم أولاً):\n');
    for (final message in recent) {
      final raw = message['content']?.toString() ?? '';
      final clipped = raw.length > 1800 ? '${raw.substring(0, 1800)}…' : raw;
      buffer.writeln('${message['isUser'] == true ? 'المستخدم' : 'المساعد'}: $clipped');
    }
    buffer.writeln('\nالطلب الحالي:');
    buffer.write(currentPrompt);
    return buffer.toString();
  }

  Future<void> _resumePendingTask() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getString('giant_pending_task');
    final pendingSession = prefs.getString('giant_pending_session_id');
    if (pending == null || pending.trim().isEmpty || !mounted) return;
    if (pendingSession != null && pendingSession != _currentSessionId) return;
    var taskId = prefs.getString('giant_pending_task_id');
    if (taskId == null || taskId.isEmpty) {
      final tracked = await TaskManager().createTask(
        pending,
        conversationId: _currentSessionId,
      );
      taskId = tracked['id'].toString();
      await prefs.setString('giant_pending_task_id', taskId);
    }

    final shortId = _currentSessionId.length > 4
        ? _currentSessionId.substring(_currentSessionId.length - 4)
        : _currentSessionId;
    final interrupted = <String, dynamic>{
      'id': 'task_interrupted_${DateTime.now().microsecondsSinceEpoch}',
      'type': 'task_interrupted',
      'title': 'توقفت مهمة قبل اكتمالها',
      'subtitle': 'الجلسة #$shortId',
      'status': 'interrupted',
      'details': 'أُغلق التطبيق قبل حفظ النتيجة النهائية. يمكن إعادة إرسال الطلب مع سياق هذه الجلسة وآخر مخرجات الأدوات المحفوظة.',
      'session_id': _currentSessionId,
    };
    await _saveAgentEvent(interrupted);
    if (!mounted) return;
    setState(() => _agentSteps.add(interrupted));

    final shouldResume = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('مهمة غير مكتملة'),
        content: const Text('تم إغلاق التطبيق أثناء تنفيذ مهمة. هل تريد إعادة إرسال الطلب مع سياق الجلسة وآخر نتائج الأدوات المحفوظة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء المهمة')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('استئناف')),
        ],
      ),
    );
    if (!mounted) return;
    if (shouldResume != true) {
      await TaskManager().markCancelled(taskId);
      await prefs.remove('giant_pending_task');
      await prefs.remove('giant_pending_session_id');
      await prefs.remove('giant_pending_task_id');
      return;
    }

    final completedTools = _agentSteps.where((event) =>
      event['status'] == 'completed' &&
      (event['type'] == 'tool_output' ||
       event['type'] == 'file_created' ||
       event['type'] == 'file_updated')
    ).toList();
    final recentTools = completedTools.length > 5
        ? completedTools.sublist(completedTools.length - 5)
        : completedTools;
    final toolContext = recentTools.isEmpty
        ? ''
        : '\n\nنتائج الأدوات المؤكدة قبل انقطاع التطبيق (الأحدث أخيراً):\n' +
            recentTools.map((event) {
              final label = event['title']?.toString() ??
                  event['tool_name']?.toString() ??
                  event['file_name']?.toString() ??
                  'أداة مكتملة';
              final result = (event['output'] ??
                      event['content'] ??
                      event['file_name'] ??
                      event['details'] ??
                      '').toString();
              final bounded = result.length > 1200
                  ? '${result.substring(0, 1200)}…'
                  : result;
              return '- $label\n$bounded';
            }).join('\n\n') +
            '\n\nاستأنف من حالة مساحة العمل الحالية. افحص ما أُنجز قبل إعادة أي عملية كتابة، ولا تكرر إجراءً مكتملاً إلا إذا أثبت الفحص الحاجة إليه.';

    setState(() => _isLoading = true);
    try {
      final response = await _runTrackedTask(
        '${_contextualPrompt(pending)}$toolContext',
        taskId: taskId,
      );
      await prefs.remove('giant_pending_task');
      await prefs.remove('giant_pending_session_id');
      await prefs.remove('giant_pending_task_id');
      if (!mounted) return;
      setState(() {
        _streamingResponse = '';
        _messages.add({'isUser': false, 'content': response, 'time': DateTime.now()});
        _isLoading = false;
      });
      await _saveMessage(response, false);
      _scrollToBottom();
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }


  Future<String> _executeChatPrompt(String prompt) async {
    var enrichedPrompt = _contextualPrompt(prompt);
    if (_webSearchEnabled) {
      if (mounted) setState(() => _thinkingStage = 'يبحث على الويب عن مصادر حديثة...');
      try {
        final results = await WebSearchService.instance.search(prompt, limit: 5);
        enrichedPrompt += '\n\nنتائج البحث المباشر على الويب (استخدم المصادر التي تدعم الإجابة وأدرج روابطها):\n'
            + WebSearchService.instance.formatForPrompt(results);
      } catch (error) {
        enrichedPrompt += '\n\nتعذر إجراء البحث على الويب: ' + error.toString()
            + '. وضّح أن البحث لم ينجح ولا تخترع نتائج.';
      }
    }
    if (_includeGithubContext) {
      if (mounted) setState(() => _thinkingStage = 'يقرأ سياق مستودع GitHub...');
      try {
        enrichedPrompt += '\n\n' + await GitHubRepositoryService.instance.buildContext();
      } catch (error) {
        enrichedPrompt += '\n\nتعذر جلب سياق مستودع GitHub: ' + error.toString();
      }
    }
    if (_agentModeEnabled) {
      final tracked = await TaskManager().createTask(prompt, conversationId: _currentSessionId);
      return _runTrackedTask(enrichedPrompt, taskId: tracked['id'].toString());
    }
    return _modelService.processChat(enrichedPrompt, conversationId: _currentSessionId);
  }

  Future<void> _setAgentMode(bool enabled) async {
    if (_isLoading) return;
    setState(() => _agentModeEnabled = enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('giant_agent_mode_enabled', enabled);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(enabled
          ? 'تم تفعيل وضع الوكيل: التخطيط والأدوات وسجل التنفيذ.'
          : 'تم تفعيل الدردشة العادية: استدلال مباشر دون مسار تنسيق الوكيل.'),
    ));
  }

  Future<void> _runExistingUserMessage(int index, {String? editedText}) async {
    if (_isLoading || index < 0 || index >= _messages.length) return;
    final user = _messages[index];
    if (user['isUser'] != true) return;
    final prompt = (editedText ?? user['content']?.toString() ?? '').trim();
    if (prompt.isEmpty) return;
    final previousRequestId = user['requestId']?.toString() ?? '';
    final oldDbId = user['dbId'];
    final requestId = DateTime.now().microsecondsSinceEpoch.toString();
    _activeAgentRequestId = requestId;
    if (oldDbId is int) {
      await _db?.delete('messages', where: 'session_id = ? AND id > ?',
          whereArgs: [_currentSessionId, oldDbId]);
      await _db?.update('messages', {
        'content': prompt,
        'request_id': requestId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }, where: 'id = ? AND session_id = ?', whereArgs: [oldDbId, _currentSessionId]);
    }
    setState(() {
      user['content'] = prompt;
      user['requestId'] = requestId;
      _messages.removeRange(index + 1, _messages.length);
      _agentSteps.removeWhere((event) => event['request_id']?.toString() == previousRequestId);
      _streamingResponse = '';
      _streamingShimmerStart = 0;
      _isLoading = true;
    });
    try {
      final response = await _executeChatPrompt(prompt);
      if (!mounted) return;
      setState(() {
        _messages.add({'isUser': false, 'content': response, 'time': DateTime.now()});
        _isLoading = false;
        _thinkingStage = '';
      });
      await _saveMessage(response, false);
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      final response = 'تعذر إكمال الطلب: $error';
      setState(() {
        _messages.add({'isUser': false, 'content': response, 'time': DateTime.now()});
        _isLoading = false;
        _thinkingStage = '';
      });
      await _saveMessage(response, false);
    }
  }

  Future<void> _editUserMessage(int index) async {
    if (index < 0 || index >= _messages.length || _isLoading) return;
    final editor = TextEditingController(text: _messages[index]['content']?.toString() ?? '');
    final edited = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const GiantPalette.surface,
        title: const Text('تعديل رسالتك', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: editor,
          autofocus: true,
          minLines: 2,
          maxLines: 7,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'عدّل نص الرسالة'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, editor.text), child: const Text('حفظ وإعادة الإرسال')),
        ],
      ),
    );
    editor.dispose();
    if (edited == null || !mounted) return;
    await _runExistingUserMessage(index, editedText: edited);
  }

  Future<void> _regenerateAssistantMessage(int index) async {
    if (_isLoading || index < 0 || index >= _messages.length || _messages[index]['isUser'] == true) return;
    var userIndex = index - 1;
    while (userIndex >= 0 && _messages[userIndex]['isUser'] != true) {
      userIndex--;
    }
    if (userIndex < 0) return;
    await _runExistingUserMessage(userIndex);
  }

  Future<void> _copyMessage(String content) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ النص.')),
    );
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading) return;

    final requestId = DateTime.now().microsecondsSinceEpoch.toString();
    _activeAgentRequestId = requestId;
    setState(() {
      _messages.add({
        'isUser': true,
        'content': text,
        'time': DateTime.now(),
        'requestId': requestId,
      });
      _controller.clear();
      _isLoading = true;
    });
    await _saveMessage(text, true, requestId: requestId);
    final current = await _db?.query('sessions',
        columns: ['title'],
        where: 'id = ?',
        whereArgs: [_currentSessionId],
        limit: 1);
    if (current != null &&
        current.isNotEmpty &&
        current.first['title'] == 'جلسة جديدة') {
      final title = text.length > 36 ? '${text.substring(0, 36)}…' : text;
      await _db?.update(
        'sessions',
        {
          'title': title,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [_currentSessionId],
      );
      await _loadSessions();
    }

    final taskPrefs = await SharedPreferences.getInstance();
    if (_agentModeEnabled) {
      await taskPrefs.setString('giant_pending_task', text);
      await taskPrefs.setString('giant_pending_session_id', _currentSessionId);
    }
    _scrollToBottom();

    String response;
    try {
      response = await _executeChatPrompt(text);
    } catch (error) {
      response = 'تعذر إكمال الطلب: $error';
    } finally {
      if (_agentModeEnabled) {
        await taskPrefs.remove('giant_pending_task');
        await taskPrefs.remove('giant_pending_session_id');
        await taskPrefs.remove('giant_pending_task_id');
      }
    }

    if (!mounted) return;
    setState(() {
      _streamingResponse = '';
      _messages.add({
        'isUser': false,
        'content': response,
        'time': DateTime.now(),
      });
      _isLoading = false;
    });
    await _saveMessage(response, false);
    _scrollToBottom();
  }

  Future<void> _pickFile() async {
    try {
      final file = await FileUploadService.instance.pickFile();
      if (file == null || !mounted) return;
      await _processFile(file);
    } catch (error) {
      if (!mounted) return;
      final message = 'تعذر استيراد الملف أو تحليله: $error';
      setState(() {
        _messages.add({'isUser': false, 'content': message, 'time': DateTime.now()});
        _isLoading = false;
      });
      await _saveMessage(message, false);
    }
  }

  Future<void> _processFile(File file) async {
    if (!mounted || _isLoading) return;
    try {
      final analysis = await FileUploadService.instance.processFile(file);
      final document = analysis['extracted_text']?.toString() ?? await file.readAsString();
      final boundedDocument = document.length > 40000
          ? '${document.substring(0, 40000)}\n[تم اقتطاع بقية الملف لحماية نافذة السياق]'
          : document;
      final attachmentMessage = 'ملف مرفق: ${analysis['filename']}\n'
          'النوع: ${analysis['extension']} • الحجم: ${analysis['size_bytes']} بايت\n'
          'البيانات الأولية: ${jsonEncode(analysis)}';
      final requestId = DateTime.now().microsecondsSinceEpoch.toString();
      _activeAgentRequestId = requestId;
      setState(() {
        _messages.add({
          'isUser': true,
          'content': attachmentMessage,
          'time': DateTime.now(),
          'requestId': requestId,
        });
        _isLoading = true;
      });
      await _saveMessage(attachmentMessage, true, requestId: requestId);
      final analysisPrompt =
          'حلّل محتوى الملف المرفق اعتماداً على النص الفعلي التالي. '
          'اذكر حدود التحليل ولا تخترع بيانات غير موجودة.\n'
          'تحليل الملف: ${jsonEncode(analysis)}\n'
          'محتوى الملف:\n$boundedDocument';
      final taskPrefs = await SharedPreferences.getInstance();
      final trackedTask = await TaskManager().createTask(
        'تحليل الملف: ${analysis['filename']}',
        conversationId: _currentSessionId,
      );
      final taskId = trackedTask['id'].toString();
      await taskPrefs.setString('giant_pending_task', analysisPrompt);
      await taskPrefs.setString('giant_pending_session_id', _currentSessionId);
      await taskPrefs.setString('giant_pending_task_id', taskId);
      final response = await _runTrackedTask(analysisPrompt, taskId: taskId);
      await taskPrefs.remove('giant_pending_task');
      await taskPrefs.remove('giant_pending_session_id');
      await taskPrefs.remove('giant_pending_task_id');
      if (!mounted) return;
      setState(() {
        _messages.add({
          'isUser': false,
          'content': response,
          'time': DateTime.now(),
        });
        _isLoading = false;
      });
      await _saveMessage(response, false);
    } catch (error) {
      if (!mounted) return;
      final message = 'تعذر استيراد الملف أو تحليله: $error';
      setState(() {
        _messages.add({'isUser': false, 'content': message, 'time': DateTime.now()});
        _isLoading = false;
      });
      await _saveMessage(message, false);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;
    final requestId = DateTime.now().microsecondsSinceEpoch.toString();
    _activeAgentRequestId = requestId;
    setState(() {
      _messages.add({
        'isUser': true,
        'content': 'صورة مرفقة: ${image.name}',
        'time': DateTime.now(),
        'requestId': requestId,
      });
      _isLoading = true;
    });
    await _saveMessage('صورة مرفقة: ${image.name}', true, requestId: requestId);
    String response;
    try {
      // The current bundled GGUF model is text-only. Report this capability
      // boundary honestly instead of asking it to guess from a filename.
      response = await ImageRecognitionService.analyzeImage(File(image.path));
    } catch (error) {
      response = 'تعذر استقبال الصورة: $error';
    }
    if (!mounted) return;
    setState(() {
      _messages.add({'isUser': false, 'content': response, 'time': DateTime.now()});
      _isLoading = false;
    });
    await _saveMessage(response, false);
  }


  Future<void> _toggleVoiceInput() async {
    if (_speech.isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }
    final available = await _speech.initialize(
      onStatus: (_) {
        if (mounted) setState(() => _isListening = _speech.isListening);
      },
      onError: (error) {
        if (mounted) {
          setState(() => _isListening = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تعذر تشغيل الإدخال الصوتي: ' + error.errorMsg)),
          );
        }
      },
    );
    if (!available || !mounted) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('خدمة التعرف على الكلام غير متاحة على هذا الجهاز.')),
      );
      return;
    }
    final locales = await _speech.locales();
    final arabic = locales.where((item) => item.localeId.toLowerCase().startsWith('ar')).toList();
    await _speech.listen(
      localeId: arabic.isNotEmpty ? arabic.first.localeId : null,
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 5),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
      ),
      onResult: (result) {
        if (!mounted || result.recognizedWords.isEmpty) return;
        setState(() {
          _controller.text = result.recognizedWords;
          _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
        });
      },
    );
    if (mounted) setState(() => _isListening = _speech.isListening);
  }

  Future<void> _openOpenRouterDialog() async {
    final keyController = TextEditingController(text: await OpenRouterService.instance.getApiKey() ?? '');
    final modelController = TextEditingController(text: await OpenRouterService.instance.getModel());
    final endpointController = TextEditingController(text: await OpenRouterService.instance.getBaseUrl());
    var enabled = await OpenRouterService.instance.isEnabled();
    var busy = false;
    var error = '';
    if (!mounted) { keyController.dispose(); modelController.dispose(); endpointController.dispose(); return; }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, updateDialog) => AlertDialog(
          backgroundColor: const GiantPalette.surface,
          title: const Text('ربط مزوّد الذكاء الاصطناعي', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('أدخل مفتاح أي مزوّد يدعم واجهة OpenAI-compatible مع عنوان API الخاص به. يُحفظ المفتاح مشفراً على الجهاز.',
                style: TextStyle(color: GiantPalette.muted, fontSize: 12)),
              const SizedBox(height: 6),
              const Text('أمثلة للعناوين: OpenRouter: https://openrouter.ai/api/v1  •  Gemini: https://generativelanguage.googleapis.com/v1beta/openai',
                style: TextStyle(color: Color(0xFF93C5FD), fontSize: 11)),
              const SizedBox(height: 12),
              TextField(controller: keyController, obscureText: true, autocorrect: false,
                decoration: const InputDecoration(labelText: 'API Key', hintText: 'أدخل مفتاح المزوّد', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(controller: endpointController, keyboardType: TextInputType.url, autocorrect: false,
                decoration: const InputDecoration(labelText: 'API Base URL', hintText: 'https://api.example.com/v1', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(controller: modelController,
                decoration: const InputDecoration(labelText: 'معرّف النموذج', hintText: 'openai/gpt-4o-mini', border: OutlineInputBorder())),
              SwitchListTile(contentPadding: EdgeInsets.zero, value: enabled,
                onChanged: (v) => updateDialog(() => enabled = v),
                title: const Text('استخدام المزوّد الخارجي للاستدلال')),
              if (error.isNotEmpty) Text(error, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              if (busy) const LinearProgressIndicator(),
            ]),
          ),
          actions: [
            TextButton(onPressed: busy ? null : () async {
              await OpenRouterService.instance.disconnect();
              if (mounted) setState(() => _openRouterEnabled = false);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم فصل المزوّد وحذف بياناته.')));
            }, child: const Text('فصل وحذف المفتاح')),
            TextButton(onPressed: busy ? null : () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            FilledButton(onPressed: busy ? null : () async {
              updateDialog(() { busy = true; error = ''; });
              try {
                if (keyController.text.trim().isNotEmpty) {
                  await OpenRouterService.instance.configure(
                    apiKey: keyController.text, model: modelController.text,
                    baseUrl: endpointController.text, enable: enabled);
                } else {
                  await OpenRouterService.instance.setEnabled(enabled);
                }
                if (mounted) setState(() => _openRouterEnabled = enabled);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(enabled ? 'تم تفعيل المزوّد: ' + modelController.text.trim() : 'تم تعطيل المزوّد.')));
              } catch (e) { updateDialog(() { busy = false; error = e.toString(); }); }
            }, child: const Text('حفظ')),
          ],
        ),
      ),
    );
    keyController.dispose();
    modelController.dispose();
    endpointController.dispose();
  }

  Future<void> _openGitHubDialog() async {
    final repositoryController = TextEditingController(
      text: await GitHubRepositoryService.instance.getRepository() ?? '');
    final tokenController = TextEditingController();
    var busy = false;
    var error = '';
    if (!mounted) { repositoryController.dispose(); tokenController.dispose(); return; }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, updateDialog) => AlertDialog(
          backgroundColor: const GiantPalette.surface,
          title: const Text('ربط مستودع GitHub', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('المستودعات العامة لا تحتاج رمزاً. للمستودعات الخاصة أدخل Personal Access Token. الربط الحالي للقراءة والسياق فقط.',
              style: TextStyle(color: GiantPalette.muted, fontSize: 12)),
            const SizedBox(height: 12),
            TextField(controller: repositoryController,
              decoration: const InputDecoration(labelText: 'رابط المستودع', hintText: 'https://github.com/owner/repository', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: tokenController, obscureText: true, autocorrect: false,
              decoration: const InputDecoration(labelText: 'GitHub Token (اختياري)', border: OutlineInputBorder())),
            if (error.isNotEmpty) Text(error, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            if (busy) const LinearProgressIndicator(),
          ])),
          actions: [
            TextButton(onPressed: busy ? null : () async {
              await GitHubRepositoryService.instance.disconnect();
              if (mounted) setState(() => _includeGithubContext = false);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم فصل مستودع GitHub.')));
            }, child: const Text('فصل المستودع')),
            TextButton(onPressed: busy ? null : () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            FilledButton(onPressed: busy ? null : () async {
              updateDialog(() { busy = true; error = ''; });
              try {
                final metadata = await GitHubRepositoryService.instance.connect(
                  repositoryUrl: repositoryController.text, token: tokenController.text);
                if (mounted) setState(() => _includeGithubContext = true);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('تم ربط ' + (metadata['full_name']?.toString() ?? 'المستودع') + ' بنجاح.')));
              } catch (e) { updateDialog(() { busy = false; error = e.toString(); }); }
            }, child: const Text('تحقق واربط')),
          ],
        ),
      ),
    );
    repositoryController.dispose();
    tokenController.dispose();
  }


  Future<void> _toggleGitHubContext() async {
    if (!await GitHubRepositoryService.instance.isConnected()) {
      await _openGitHubDialog();
      return;
    }
    if (!mounted) return;
    setState(() => _includeGithubContext = !_includeGithubContext);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_includeGithubContext
        ? 'سيُرفق سياق مستودع GitHub مع الطلب التالي.'
        : 'تم إيقاف إرفاق سياق المستودع.'),
    ));
  }

  Future<void> _openCloudDialog() async {
    final config = await CloudStorageService.instance.getConfiguration();
    final serverController = TextEditingController(text: config['server'] ?? '');
    final userController = TextEditingController(text: config['username'] ?? '');
    final passwordController = TextEditingController(text: config['password'] ?? '');
    var busy = false;
    var error = '';
    if (!mounted) { serverController.dispose(); userController.dispose(); passwordController.dispose(); return; }
    final shouldUpload = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, updateDialog) => AlertDialog(
          backgroundColor: const GiantPalette.surface,
          title: const Text('اتصال السحابة', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('يدعم Nextcloud وأي خادم WebDAV. استخدم كلمة مرور تطبيق مخصصة.',
              style: TextStyle(color: GiantPalette.muted, fontSize: 12)),
            const SizedBox(height: 12),
            TextField(controller: serverController, keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'عنوان الخادم', hintText: 'https://cloud.example.com', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: userController,
              decoration: const InputDecoration(labelText: 'اسم المستخدم', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: passwordController, obscureText: true,
              decoration: const InputDecoration(labelText: 'كلمة مرور التطبيق', border: OutlineInputBorder())),
            if (error.isNotEmpty) Text(error, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            if (busy) const LinearProgressIndicator(),
          ])),
          actions: [
            TextButton(onPressed: busy ? null : () async {
              await CloudStorageService.instance.disconnect();
              if (dialogContext.mounted) Navigator.pop(dialogContext, false);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم فصل السحابة وحذف بيانات الاتصال.')));
            }, child: const Text('فصل')),
            TextButton(onPressed: busy ? null : () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
            FilledButton(onPressed: busy ? null : () async {
              updateDialog(() { busy = true; error = ''; });
              try {
                await CloudStorageService.instance.configure(
                  server: serverController.text, username: userController.text,
                  appPassword: passwordController.text);
                if (dialogContext.mounted) Navigator.pop(dialogContext, true);
              } catch (e) { updateDialog(() { busy = false; error = e.toString(); }); }
            }, child: const Text('حفظ ورفع مساحة العمل')),
          ],
        ),
      ),
    );
    serverController.dispose(); userController.dispose(); passwordController.dispose();
    if (shouldUpload != true || !mounted) return;
    try {
      final exported = await _modelService.exportWorkspace();
      final path = exported['path']?.toString();
      if (path == null || path.isEmpty) throw StateError('لم يتم إنشاء ملف مساحة العمل.');
      final remote = await CloudStorageService.instance.uploadWorkspace(File(path));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم رفع مساحة العمل إلى السحابة: ' + remote.pathSegments.last)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر رفع مساحة العمل: ' + e.toString())));
    }
  }


  Future<void> _activateSessionFromHistory(ChatSession session) async {
    if (_isLoading || session.id == _currentSessionId) return;
    _currentSessionId = session.id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('giant_active_session_id', session.id);
    await _loadHistory();
  }

  Future<void> _showConversationHistory() async {
    await _loadSessions();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF18181B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * .72,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                child: Row(
                  children: [
                    const Icon(Icons.forum_outlined, color: Color(0xFF60A5FA)),
                    const SizedBox(width: 10),
                    const Expanded(child: Text('المحادثات السابقة',
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700))),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _createNewSession();
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('جديدة'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFF303036)),
              Expanded(
                child: _sessions.isEmpty
                    ? const Center(child: Text('لا توجد محادثات محفوظة', style: TextStyle(color: GiantPalette.muted)))
                    : ListView.separated(
                        itemCount: _sessions.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 60, color: Color(0xFF29292F)),
                        itemBuilder: (context, index) {
                          final session = _sessions[index];
                          final active = session.id == _currentSessionId;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: active ? const Color(0xFF1D4ED8) : const Color(0xFF29292F),
                              child: Icon(active ? Icons.chat : Icons.chat_bubble_outline, color: Colors.white, size: 18),
                            ),
                            title: Text(session.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.white, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
                            subtitle: Text(
                              '${session.updatedAt.year}/${session.updatedAt.month.toString().padLeft(2, '0')}/${session.updatedAt.day.toString().padLeft(2, '0')}',
                              style: const TextStyle(color: GiantPalette.muted, fontSize: 11),
                            ),
                            trailing: IconButton(
                              tooltip: 'حذف المحادثة',
                              icon: const Icon(Icons.delete_outline, color: GiantPalette.muted, size: 19),
                              onPressed: _isLoading ? null : () async {
                                Navigator.pop(sheetContext);
                                await _deleteSession(session);
                                if (mounted) _showConversationHistory();
                              },
                            ),
                            onTap: () {
                              Navigator.pop(sheetContext);
                              _activateSessionFromHistory(session);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _shareCurrentConversation() async {
    if (_messages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد رسائل لمشاركتها بعد.')),
      );
      return;
    }
    final content = _messages.map((message) {
      final role = message['isUser'] == true ? 'أنت' : 'Giant Agent';
      return '$role:\n${message['content']}';
    }).join('\n\n');
    try {
      await Share.share('محادثة Giant Agent\n\n$content', subject: 'محادثة Giant Agent');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذرت مشاركة المحادثة: $error')),
        );
      }
    }
  }

  Future<void> _showAgentInformation() async {
    final openRouterEnabled = await OpenRouterService.instance.isEnabled();
    final modelName = openRouterEnabled
        ? await OpenRouterService.instance.getModel()
        : _activeModel['name']?.toString();
    if (!mounted) return;
    final provider = openRouterEnabled ? 'OpenRouter' : 'محلي (GGUF)';
    final selectedModel = modelName?.isNotEmpty == true
        ? modelName!
        : 'لم يتم تحديد نموذج';
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const GiantPalette.surface,
        title: const Text('Giant Agent X', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('الإصدار 2.0', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            Text('مزود الاستدلال: $provider',
              style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Text('النموذج النشط: $selectedModel',
              style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Text('المحادثات المحفوظة: ${_sessions.length}',
              style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            const Text(
              'يعمل الوكيل محلياً افتراضياً، ويمكن اختيار OpenRouter كمزود استدلال خارجي.',
              style: TextStyle(color: GiantPalette.muted, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  void _newConversation() => _createNewSession();

  void _switchModel(Map<String, dynamic> model) async {
    if (model['id'] == 'no_model') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد نموذج محدد')),
      );
      return;
    }
    
    final success = await _modelService.switchModel(model['id']);
    if (success && mounted) {
      setState(() {
        _activeModel = _modelService.getActiveModel();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم التبديل إلى: ${model['name']}')),
      );
      Navigator.pop(context);
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _agentEventSubscription?.cancel();
    _kernelEventSubscription?.cancel();
    _speech.stop();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  IconData _agentStepIcon(String type) {
    switch (type) {
      case 'code':
      case 'tool_code': return Icons.code;
      case 'file':
      case 'file_created': return Icons.insert_drive_file_outlined;
      case 'terminal':
      case 'terminal_run':
      case 'tool_start':
      case 'tool_output': return Icons.terminal;
      case 'todo': return Icons.checklist;
      case 'thought': return Icons.psychology_alt_outlined;
      case 'task_interrupted': return Icons.pause_circle_outline;
      case 'tool_error': return Icons.error_outline;
      default: return Icons.circle_outlined;
    }
  }

  bool _stepIsSvg(Map<String, dynamic> step) {
    final type = step['type']?.toString().toLowerCase() ?? '';
    final mime = step['mime_type']?.toString().toLowerCase() ?? '';
    final fileName = step['file_name']?.toString().toLowerCase() ?? '';
    final payload = '${step['content'] ?? ''} ${step['output'] ?? ''}'.toLowerCase();
    return mime.contains('image/svg+xml') ||
        fileName.endsWith('.svg') ||
        type.contains('svg') ||
        payload.contains('<svg');
  }

  bool _opensTerminalFromStep(Map<String, dynamic> step) {
    final type = step['type']?.toString().toLowerCase() ?? '';
    final title = step['title']?.toString().toLowerCase() ?? '';
    final toolName = step['tool_name']?.toString().toLowerCase() ?? '';
    return toolName == 'execute_python' ||
        type == 'terminal' ||
        type == 'terminal_run' ||
        type == 'terminal_output' ||
        title.contains('طرفية') ||
        title.contains('terminal') ||
        _stepIsSvg(step);
  }

  void _showAgentStep(Map<String, dynamic> step) {
    if (_opensTerminalFromStep(step)) {
      _showTerminal(step: step);
      return;
    }
    final title = step['title']?.toString() ?? 'تفاصيل التنفيذ';
    final fileName = step['file_name']?.toString();
    final content = step['content']?.toString();
    final command = step['command']?.toString();
    final output = step['output']?.toString();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101820),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .72,
        maxChildSize: .94,
        minChildSize: .35,
        builder: (context, controller) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
              child: Row(children: [
                const Icon(Icons.computer, color: Colors.tealAccent),
                const SizedBox(width: 9),
                Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white70)),
              ]),
            ),
            if (fileName != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: Text(fileName, style: const TextStyle(color: Colors.tealAccent, fontSize: 12))),
            if (command != null) Padding(padding: const EdgeInsets.all(18), child: SelectableText('\$ $command', style: const TextStyle(color: Colors.lightGreenAccent, fontFamily: 'monospace'))),
            Expanded(child: SingleChildScrollView(
              controller: controller,
              padding: const EdgeInsets.all(18),
              child: SelectableText(
                content ?? output ?? step['details']?.toString() ?? 'لا توجد تفاصيل إضافية.',
                style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.5, fontFamily: 'monospace'),
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildAgentTimeline(List<Map<String, dynamic>> steps, String requestId) {
    if (steps.isEmpty) return const SizedBox.shrink();
    final expanded = !_collapsedTimelineIds.contains(requestId);
    const cardColor = Color(0xFF1E1E1E);
    const mutedColor = Color(0xFF9CA3AF);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(.045)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() {
              if (expanded) { _collapsedTimelineIds.add(requestId); } else { _collapsedTimelineIds.remove(requestId); }
            }),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 13, 12, 13),
              child: Row(
                children: [
                  const Icon(Icons.account_tree_outlined, color: mutedColor, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('سجل تنفيذ الوكيل',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Text('${steps.length} أحداث من المحرك',
                          style: const TextStyle(color: mutedColor, fontSize: 10)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'فتح الطرفية',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.terminal, color: Color(0xFF0D8274), size: 20),
                    onPressed: _showTerminal,
                  ),
                  IconButton(
                    tooltip: 'فتح مساحة عمل الوكيل',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.computer_outlined, color: Color(0xFF0D8274), size: 19),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => AgentWorkspaceScreen(steps: List<Map<String, dynamic>>.from(steps)),
                    )),
                  ),
                  Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: mutedColor, size: 20),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: expanded
                ? Column(
                    children: List.generate(steps.length, (index) {
                      final step = steps[index];
                      final status = step['status']?.toString() ?? 'completed';
                      final failed = status == 'failed' || status == 'interrupted';
                      final running = status == 'running';
                      final pending = status == 'pending';
                      final type = step['type']?.toString() ?? 'thought';
                      final icon = _agentStepIcon(type);
                      final color = failed
                          ? const Color(0xFFEF6A6A)
                          : (running ? const Color(0xFF0D8274) : mutedColor);
                      final title = step['title']?.toString() ?? 'حدث من الوكيل';
                      final subtitle = step['subtitle']?.toString();
                      final opensTerminal = _opensTerminalFromStep(step);
                      final hasPreview = opensTerminal ||
                          step['content'] != null ||
                          step['output'] != null ||
                          step['command'] != null ||
                          step['details'] != null ||
                          step['file_name'] != null;
                      final toolName = step['tool_name']?.toString() ?? '';
                      final isTool = toolName.isNotEmpty ||
                          type.contains('tool') ||
                          type.contains('terminal') ||
                          type == 'file_created' ||
                          type == 'file_updated' ||
                          type == 'file_read' ||
                          _stepIsSvg(step);
                      final statusLabel = running
                          ? 'قيد التنفيذ'
                          : pending
                              ? 'بانتظار التنفيذ'
                              : failed
                                  ? (status == 'interrupted' ? 'متوقف' : 'فشل')
                                  : 'مكتمل';
                      return InkWell(
                        onTap: hasPreview ? () => _showAgentStep(step) : null,
                        child: Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(12, 7, 12, 7),
                          child: Row(
                            children: [
                              Container(
                                width: 20,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2A2A2A),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                alignment: Alignment.center,
                                child: Icon(icon, size: 13, color: isTool ? const Color(0xFF0D8274) : mutedColor),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (running)
                                      AgentShimmerText(
                                        title,
                                        maxLines: 1,
                                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                                      )
                                    else
                                      Text(title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: failed ? const Color(0xFFFF9292) : Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        )),
                                    if (subtitle != null && subtitle.isNotEmpty && !subtitle.contains('الجلسة #'))
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: mutedColor, fontSize: 10)),
                                      ),
                                    const SizedBox(height: 3),
                                    Text(statusLabel,
                                      style: TextStyle(
                                        color: failed
                                            ? const Color(0xFFFF9292)
                                            : running
                                                ? const GiantPalette.primaryLight
                                                : mutedColor,
                                        fontSize: 9,
                                      )),
                                  ],
                                ),
                              ),
                              if (hasPreview)
                                const Padding(
                                  padding: EdgeInsetsDirectional.only(start: 5),
                                  child: Icon(Icons.chevron_right, size: 17, color: mutedColor),
                                ),
                              const SizedBox(width: 5),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: running
                                    ? const AgentPulseDot(key: ValueKey('running'), size: 9)
                                    : pending
                                        ? const Icon(
                                            Icons.schedule_rounded,
                                            key: ValueKey('pending'),
                                            color: Color(0xFF6B7280),
                                            size: 14,
                                          )
                                        : Icon(
                                            key: ValueKey(failed ? 'failed' : 'completed'),
                                            failed
                                                ? Icons.error_outline
                                                : status == 'interrupted'
                                                    ? Icons.pause_circle_outline
                                                    : Icons.check_circle,
                                            color: color,
                                            size: 15,
                                          ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  )
                : const SizedBox(width: double.infinity),
          ),
          if (expanded)
            const SizedBox(height: 7),
        ],
      ),
    );
  }


  Widget _messageActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 34, height: 30),
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: Icon(icon, size: 16, color: const GiantPalette.muted),
      ),
    );
  }

  Widget _composerIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    Color foreground = const GiantPalette.muted,
    Color background = const GiantPalette.border,
    bool prominent = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(prominent ? 20 : 13),
        child: InkWell(
          borderRadius: BorderRadius.circular(prominent ? 20 : 13),
          onTap: onPressed,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(icon, color: foreground, size: prominent ? 18 : 17),
          ),
        ),
      ),
    );
  }

  Widget _composerPillButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: const GiantPalette.border,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: const GiantPalette.muted, size: 15),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(color: GiantPalette.muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _drawerActionTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Color iconColor = const GiantPalette.primaryLight,
    Color titleColor = const GiantPalette.text,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 1),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, color: iconColor, size: 19),
      ),
      title: Text(title, style: TextStyle(color: titleColor, fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: subtitle == null ? null : Text(subtitle, style: const TextStyle(color: Color(0xFF8294A8), fontSize: 10)),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const GiantPalette.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 56,
        backgroundColor: const GiantPalette.background,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leadingWidth: 44,
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: 'القائمة',
            onPressed: () => Scaffold.of(context).openDrawer(),
            icon: const Icon(Icons.menu_rounded, size: 21),
          ),
        ),
        titleSpacing: 0,
        title: PopupMenuButton<String>(
          tooltip: 'إصدار الوكيل',
          offset: const Offset(0, 42),
          color: const GiantPalette.elevated,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (value) {
            if (value == 'github') {
              _openGitHubDialog();
            } else if (value == 'cloud') {
              _openCloudDialog();
            } else if (value == 'openrouter') {
              _openOpenRouterDialog();
            } else if (value == 'workflow') {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AgentWorkflowScreen()),
              );
            } else if (value == 'settings') {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'workflow', child: Text('سير تنفيذ الوكيل')),
            PopupMenuItem(value: 'github', child: Text('ربط مستودع GitHub')),
            PopupMenuItem(value: 'cloud', child: Text('اتصال السحابة')),
            PopupMenuItem(value: 'openrouter', child: Text('مفتاح OpenRouter')),
            PopupMenuItem(value: 'settings', child: Text('الإعدادات')),
          ],
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.keyboard_arrow_down_rounded, color: GiantPalette.muted, size: 19),
              SizedBox(width: 5),
              Text('2.0', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'محادثة جديدة',
            onPressed: _newConversation,
            icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 17),
            style: IconButton.styleFrom(
              backgroundColor: const GiantPalette.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              fixedSize: const Size(32, 32),
            ),
          ),
          IconButton(
            tooltip: 'تصدير مساحة العمل',
            onPressed: _exportWorkspace,
            icon: const Icon(Icons.ios_share_rounded, color: GiantPalette.muted, size: 17),
          ),
          IconButton(
            tooltip: 'مساحة عمل الجلسة — سير الوكيل ومخرجاته',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AgentWorkflowScreen()),
            ),
            icon: const Icon(Icons.account_tree_rounded, color: GiantPalette.primaryLight, size: 18),
          ),
          PopupMenuButton<String>(
            tooltip: 'المزيد',
            icon: const Icon(Icons.more_horiz_rounded, color: GiantPalette.muted, size: 19),
            color: const GiantPalette.elevated,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
            onSelected: (value) {
              switch (value) {
                case 'desktop':
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AgentWorkspaceScreen(
                        steps: List<Map<String, dynamic>>.from(_agentSteps),
                      ),
                    ),
                  );
                  break;
                case 'refresh':
                  _refreshModels();
                  break;
                case 'history':
                  _showConversationHistory();
                  break;
                case 'share':
                  _shareCurrentConversation();
                  break;
                case 'about':
                  _showAgentInformation();
                  break;
                case 'clearHistory':
                  _clearHistory();
                  break;
                case 'github':
                  _openGitHubDialog();
                  break;
                case 'cloud':
                  _openCloudDialog();
                  break;
                case 'openrouter':
                  _openOpenRouterDialog();
                  break;
                case 'settings':
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'desktop', child: Text('سطح المكتب')),
              PopupMenuItem(value: 'refresh', child: Text('تحديث النماذج')),
              PopupMenuItem(value: 'history', child: Text('المحادثات السابقة')),
              PopupMenuItem(value: 'share', child: Text('مشاركة المحادثة الحالية')),
              PopupMenuItem(value: 'about', child: Text('حول Giant Agent')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'clearHistory', child: Text('مسح سجل المحادثة')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'github', child: Text('ربط مستودع GitHub')),
              PopupMenuItem(value: 'cloud', child: Text('اتصال السحابة')),
              PopupMenuItem(value: 'openrouter', child: Text('مفتاح OpenRouter')),
              PopupMenuItem(value: 'settings', child: Text('الإعدادات')),
            ],
          ),
          const SizedBox(width: 5),
        ],
      ),
      drawer: Drawer(
        width: MediaQuery.of(context).size.width < 386
            ? MediaQuery.of(context).size.width * 0.88
            : 340,
        backgroundColor: const GiantPalette.surface,
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [GiantPalette.surface, GiantPalette.surface],
                  ),
                  border: Border(bottom: BorderSide(color: GiantPalette.border)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const GiantPalette.primaryLight.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const GiantPalette.primaryLight.withOpacity(0.35)),
                      ),
                      child: const Icon(Icons.bolt_rounded, color: GiantPalette.primaryLight, size: 30),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Giant Agent X', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700)),
                          SizedBox(height: 4),
                          Text('مساحة الوكيل الذكي', style: TextStyle(color: Color(0xFF9CAFC2), fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Text('إجراءات سريعة', style: TextStyle(color: Color(0xFF8FA3B8), fontSize: 11, fontWeight: FontWeight.w700)),
              ),
              _drawerActionTile(
                icon: Icons.add_comment_rounded,
                title: 'جلسة جديدة',
                subtitle: 'ابدأ محادثة مستقلة',
                onTap: () { Navigator.pop(context); _createNewSession(); },
              ),
              _drawerActionTile(
                icon: Icons.file_open_rounded,
                title: 'استيراد نموذج',
                subtitle: 'تحميل نموذج GGUF من الجهاز',
                onTap: () { Navigator.pop(context); _importModel(); },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 7),
                child: Row(
                  children: [
                    const Expanded(child: Text('سجل المحادثات', style: TextStyle(color: Color(0xFF8FA3B8), fontSize: 11, fontWeight: FontWeight.w700))),
                    Text('${_sessions.length}', style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                  ],
                ),
              ),
              SizedBox(
                height: 260,
                child: _sessions.isEmpty
                    ? const Center(child: Text('لا توجد جلسات سابقة', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        itemCount: _sessions.length,
                        itemBuilder: (context, index) {
                          final session = _sessions[index];
                          final selected = session.id == _currentSessionId;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            decoration: BoxDecoration(
                              color: selected ? const Color(0xFF1E3A50) : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              border: selected ? Border.all(color: const GiantPalette.primaryLight.withOpacity(0.25)) : null,
                            ),
                            child: ListTile(
                              dense: true,
                              visualDensity: const VisualDensity(vertical: -2),
                              leading: Icon(selected ? Icons.chat_rounded : Icons.chat_bubble_outline_rounded,
                                  size: 19, color: selected ? const GiantPalette.primaryLight : const Color(0xFF8294A8)),
                              title: Text(session.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: selected ? Colors.white : const Color(0xFFD5DEE8), fontSize: 12, fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
                              subtitle: Text(session.updatedAt.toLocal().toString().substring(0, 16),
                                  style: const TextStyle(color: Color(0xFF718096), fontSize: 10)),
                              trailing: IconButton(
                                tooltip: 'حذف الجلسة',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.delete_outline_rounded, size: 17, color: Color(0xFF718096)),
                                onPressed: () => _deleteSession(session),
                              ),
                              onTap: () => _switchSession(session),
                            ),
                          );
                        },
                      ),
              ),
              _drawerActionTile(
                icon: Icons.delete_sweep_outlined,
                title: 'مسح جميع الجلسات',
                iconColor: const Color(0xFFF87171),
                titleColor: const Color(0xFFFCA5A5),
                onTap: () { Navigator.pop(context); _clearAllSessions(); },
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Divider(color: Color(0xFF263445), height: 18),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
                child: Row(
                  children: [
                    const Expanded(child: Text('النماذج المتاحة', style: TextStyle(color: Color(0xFF8FA3B8), fontSize: 11, fontWeight: FontWeight.w700))),
                    Text('${_models.length}', style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                  ],
                ),
              ),
              SizedBox(
                height: 190,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: _models.length,
                  itemBuilder: (context, index) {
                    final model = _models[index];
                    final isActive = model['id'] == _activeModel['id'];
                    return ListTile(
                      dense: true,
                      visualDensity: const VisualDensity(vertical: -2),
                      leading: Icon(isActive ? Icons.check_circle_rounded : Icons.circle_outlined,
                          size: 19, color: isActive ? const Color(0xFF34D399) : const Color(0xFF64748B)),
                      title: Text(model['name'], maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: isActive ? Colors.white : const Color(0xFFD5DEE8), fontSize: 12, fontWeight: isActive ? FontWeight.w600 : FontWeight.normal)),
                      subtitle: Text('${model['size']} • ${model['type']}', style: const TextStyle(color: Color(0xFF718096), fontSize: 10)),
                      trailing: isActive
                          ? const Text('نشط', style: TextStyle(color: Color(0xFF34D399), fontSize: 10, fontWeight: FontWeight.w700))
                          : null,
                      onTap: () => _switchModel(model),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      body: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xFF18181B),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF27272A), width: 0.7),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg['isUser'] as bool;
                final requestId = msg['requestId']?.toString() ?? '';
                final messageEvents = isUser && requestId.isNotEmpty
                    ? _agentSteps.where((event) =>
                        event['request_id']?.toString() == requestId &&
                        !_isLiveInferenceStatus(event)).toList()
                    : <Map<String, dynamic>>[];
                return Column(
                  crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                  alignment: isUser ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                  child: Container(
                    margin: const EdgeInsetsDirectional.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.8,
                    ),
                    decoration: BoxDecoration(
                      color: isUser ? const Color(0xFF0D8274) : const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isUser ? 16 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 16),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Directionality(
                          textDirection: _contentDirection(msg['content']?.toString() ?? ''),
                          child: SelectableText(
                            msg['content'],
                            textAlign: TextAlign.start,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${(msg['time'] as DateTime).hour.toString().padLeft(2, '0')}:${(msg['time'] as DateTime).minute.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.white60,
                          ),
                        ),
                      ],
                    ),
                  ),
                    ),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 8, end: 8, bottom: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _messageActionButton(
                            icon: Icons.copy_rounded,
                            tooltip: 'نسخ الرسالة',
                            onPressed: () => _copyMessage(msg['content']?.toString() ?? ''),
                          ),
                          if (isUser)
                            _messageActionButton(
                              icon: Icons.edit_outlined,
                              tooltip: 'تعديل الرسالة',
                              onPressed: _isLoading ? null : () => _editUserMessage(index),
                            )
                          else
                            _messageActionButton(
                              icon: Icons.refresh_rounded,
                              tooltip: 'إعادة توليد الإجابة',
                              onPressed: _isLoading ? null : () => _regenerateAssistantMessage(index),
                            ),
                        ],
                      ),
                    ),
                    if (messageEvents.isNotEmpty)
                      Align(
                        alignment: isUser ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .86),
                          child: _buildAgentTimeline(messageEvents, requestId),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          // The composer owns the single live status indicator. This area is
          // reserved for actual streamed answer text, never a second spinner/status.
          if (_isLoading && _streamingResponse.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const GiantPalette.primaryLight.withOpacity(.12)),
              ),
              child: Directionality(
                textDirection: _contentDirection(_streamingResponse),
                child: AgentStreamingText(
                  _streamingResponse,
                  shimmerFrom: _streamingShimmerStart,
                  selectable: true,
                  style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.55),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Container(
              constraints: const BoxConstraints(minHeight: 96, maxHeight: 136),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: const Color(0xFF222226),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF303036), width: 0.7),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isLoading || !_modelService.hasActiveModel())
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _isLoading
                                  ? const GiantPalette.primary
                                  : const Color(0xFFF59E0B),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _isLoading
                                  ? (_thinkingStage.isEmpty ? 'يعمل الوكيل...' : _thinkingStage)
                                  : (_openRouterEnabled ? 'OpenRouter متصل وجاهز للاستدلال' : 'لا يوجد نموذج نشط — استورد نموذج GGUF من القائمة'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: GiantPalette.muted,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: true,
                      minLines: 1,
                      maxLines: 4,
                      textAlign: TextAlign.start,
                      textDirection: TextDirection.rtl,
                      keyboardType: TextInputType.multiline,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.35,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'أرسل رسالة إلى Giant Agent...',
                        hintStyle: TextStyle(
                          color: GiantPalette.muted,
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    textDirection: TextDirection.ltr,
                    children: [
                      _composerIconButton(
                        icon: _isLoading ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                        tooltip: _isLoading ? 'إيقاف الوكيل' : 'إرسال الرسالة',
                        background: _isLoading ? Colors.white : const GiantPalette.primary,
                        foreground: _isLoading ? const Color(0xFF18181B) : Colors.white,
                        onPressed: _isLoading ? _cancelAgent : _sendMessage,
                        prominent: true,
                      ),
                      const SizedBox(width: 8),
                      _composerIconButton(
                        icon: _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                        tooltip: _isListening ? 'إيقاف الإدخال الصوتي' : 'الإملاء الصوتي',
                        foreground: _isListening ? Colors.white : const GiantPalette.muted,
                        background: _isListening ? const GiantPalette.primary : const GiantPalette.border,
                        onPressed: _toggleVoiceInput,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                      _composerIconButton(
                        icon: Icons.public_rounded,
                        tooltip: _webSearchEnabled ? 'إيقاف البحث المباشر' : 'تفعيل البحث التفاعلي على الويب',
                        foreground: _webSearchEnabled ? Colors.white : const GiantPalette.muted,
                        background: _webSearchEnabled ? const GiantPalette.primary : const GiantPalette.border,
                        onPressed: () {
                          setState(() => _webSearchEnabled = !_webSearchEnabled);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(_webSearchEnabled ? 'البحث المباشر مفعّل للرسائل التالية.' : 'تم إيقاف البحث المباشر.')));
                        },
                      ),
                      const SizedBox(width: 6),
                      _composerIconButton(
                        icon: Icons.key_rounded,
                        tooltip: _openRouterEnabled ? 'إعدادات OpenRouter — متصل' : 'إدخال مفتاح OpenRouter',
                        foreground: _openRouterEnabled ? const Color(0xFF4ADE80) : const GiantPalette.muted,
                        onPressed: _openOpenRouterDialog,
                      ),
                      const SizedBox(width: 6),
                      _composerIconButton(
                        icon: Icons.code_rounded,
                        tooltip: _includeGithubContext ? 'مستودع GitHub متصل — إدارة الاتصال' : 'ربط مستودع GitHub',
                        foreground: _includeGithubContext ? const Color(0xFF4ADE80) : const GiantPalette.muted,
                        onPressed: _toggleGitHubContext,
                      ),
                      const SizedBox(width: 6),
                      _composerPillButton(
                        icon: Icons.cloud_outlined,
                        label: 'السحابة',
                        onPressed: _openCloudDialog,
                      ),
                      const SizedBox(width: 6),
                      _composerPillButton(
                        icon: _agentModeEnabled ? Icons.smart_toy_rounded : Icons.chat_bubble_outline_rounded,
                        label: _agentModeEnabled ? 'وكيل' : 'عادي',
                        onPressed: () => _setAgentMode(!_agentModeEnabled),
                      ),
                      const SizedBox(width: 6),
                      _composerIconButton(
                        icon: Icons.account_tree_outlined,
                        tooltip: 'سير تنفيذ الوكيل',
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const AgentWorkflowScreen()),
                        ),
                      ),
                      const SizedBox(width: 7),
                      PopupMenuButton<String>(
                        tooltip: 'إضافة مرفق أو إجراء',
                        color: const GiantPalette.border,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        onSelected: (value) {
                          switch (value) {
                            case 'file':
                              _pickFile();
                              break;
                            case 'image':
                              _pickImage();
                              break;
                            case 'model':
                              _importModel();
                              break;
                            case 'new':
                              _newConversation();
                              break;
                            case 'github':
                              _openGitHubDialog();
                              break;
                            case 'cloud':
                              _openCloudDialog();
                              break;
                            case 'openrouter':
                              _openOpenRouterDialog();
                              break;
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'file', child: Text('إرفاق ملف')),
                          PopupMenuItem(value: 'image', child: Text('إرفاق صورة')),
                          PopupMenuItem(value: 'model', child: Text('استيراد نموذج')),
                          PopupMenuDivider(),
                          PopupMenuItem(value: 'github', child: Text('ربط مستودع GitHub')),
                          PopupMenuItem(value: 'cloud', child: Text('اتصال السحابة')),
                          PopupMenuItem(value: 'openrouter', child: Text('مفتاح OpenRouter')),
                          PopupMenuDivider(),
                          PopupMenuItem(value: 'new', child: Text('محادثة جديدة')),
                        ],
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const GiantPalette.border,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
                        ),
                      ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
            ],
          ),
        ),
      ),
    );
  }
}
