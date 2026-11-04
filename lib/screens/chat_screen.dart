import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import '../services/model_service.dart';
import '../services/file_upload_service.dart';
import '../services/image_recognition_service.dart';
import 'agent_workspace_screen.dart';
import 'agent_workflow_screen.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_screen.dart';
import '../models/chat_session.dart';
import 'dart:convert';

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
  StreamSubscription<dynamic>? _agentEventSubscription;
  final List<Map<String, dynamic>> _agentSteps = [];
  String _streamingResponse = '';
  String _toolStreamBuffer = '';
  bool _insideToolCall = false;
  static const String _toolCallOpen = '<tool_call>';
  static const String _toolCallClose = '</tool_call>';
  final Terminal _terminal = Terminal(maxLines: 5000);

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
    if (step['tool_name'] == 'execute_python') {
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
      final token = step['text']?.toString() ?? '';
      final visible = _visibleAnswerDelta(token);
      if (visible.isNotEmpty) setState(() => _streamingResponse += visible);
      _scrollToBottom();
      return;
    }
    step.putIfAbsent('session_id', () => _currentSessionId);
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
    AgentWorkflowScreen.publish(_agentSteps);
    _scrollToBottom();
  }

  Future<String> _generateWithStages(String prompt) async {
    _toolStreamBuffer = '';
    _insideToolCall = false;
    if (mounted) setState(() { _streamingResponse = ''; _thinkingStage = 'بانتظار أحداث المحرك المحلي...'; });
    try {
      return await _modelService.processInput(prompt);
    } finally {
      final tail = _flushVisibleAnswerBuffer();
      if (mounted) setState(() {
        if (tail.isNotEmpty) _streamingResponse += tail;
        _thinkingStage = '';
      });
    }
  }
  List<Map<String, dynamic>> _models = [];
  Map<String, dynamic> _activeModel = {};
  Database? _db;
  String _currentSessionId = '';
  List<ChatSession> _sessions = [];
  bool _sessionReady = false;

  @override
  void initState() {
    super.initState();
    _initDatabase();
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
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''CREATE TABLE sessions (
          id TEXT PRIMARY KEY, title TEXT NOT NULL,
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
        )''');
        await db.execute('''CREATE TABLE messages (
          id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL,
          content TEXT, isUser INTEGER, timestamp INTEGER
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
      },
    );
    await _ensureCurrentSession();
    await _loadSessions();
    await _loadHistory();
    await _init();
    await _resumePendingTask();
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

  Future<void> _loadHistory() async {
    final messages = await _db?.query('messages', where: 'session_id = ?', whereArgs: [_currentSessionId], orderBy: 'timestamp ASC');
    final events = await _db?.query('agent_events', where: 'session_id = ?', whereArgs: [_currentSessionId], orderBy: 'timestamp ASC');
    if (!mounted) return;
    setState(() {
      _messages
        ..clear()
        ..addAll((messages ?? []).map((msg) => {
          'isUser': msg['isUser'] == 1,
          'content': msg['content'] as String,
          'time': DateTime.fromMillisecondsSinceEpoch(msg['timestamp'] as int),
        }));
      _agentSteps
        ..clear()
        ..addAll((events ?? []).map((row) => Map<String, dynamic>.from(jsonDecode(row['event_json'] as String) as Map)));
    });
    AgentWorkflowScreen.publish(_agentSteps);
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
    AgentWorkflowScreen.publish(_agentSteps);
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

  Future<void> _saveMessage(String content, bool isUser) async {
    if (!_sessionReady || _currentSessionId.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db?.insert('messages', {
      'session_id': _currentSessionId,
      'content': content,
      'isUser': isUser ? 1 : 0,
      'timestamp': now,
    });
    await _db?.update('sessions', {'updated_at': now},
      where: 'id = ?', whereArgs: [_currentSessionId]);
    await _loadSessions();
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
              setState(() { _messages.clear(); _agentSteps.clear(); });
              AgentWorkflowScreen.publish(_agentSteps);
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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF050A0F),
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * .72,
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
                IconButton(onPressed: () => _terminal.write('\x1B[2J\x1B[H'), icon: const Icon(Icons.delete_sweep, color: Colors.white70)),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white70)),
              ]),
            ),
            const Divider(height: 1, color: Colors.white24),
            Expanded(child: TerminalView(_terminal, readOnly: true)),
          ],
        ),
      ),
    );
  }

  Future<void> _init() async {
    await _modelService.init();
    if (!mounted) return;
    setState(() {
      _models = _modelService.getModels();
      _activeModel = _modelService.getActiveModel();
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
      final stopped = await _modelService.cancelGeneration();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(stopped
            ? 'تم إرسال طلب إيقاف التوليد.'
            : 'تم تسجيل طلب الإيقاف؛ ستتوقف دورة الوكيل بعد الأداة الحالية.')),
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
    final buffer = StringBuffer('سياق الجلسة الحالية فقط (آخر خمس رسائل، الأقدم أولاً):\\n');
    for (final message in recent) {
      final raw = message['content']?.toString() ?? '';
      final clipped = raw.length > 1800 ? '${raw.substring(0, 1800)}…' : raw;
      buffer.writeln('${message['isUser'] == true ? 'المستخدم' : 'المساعد'}: $clipped');
    }
    buffer.writeln('\\nالطلب الحالي:');
    buffer.write(currentPrompt);
    return buffer.toString();
  }

  Future<void> _resumePendingTask() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getString('giant_pending_task');
    final pendingSession = prefs.getString('giant_pending_session_id');
    if (pending == null || pending.trim().isEmpty || !mounted) return;
    if (pendingSession != null && pendingSession != _currentSessionId) return;

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
      await prefs.remove('giant_pending_task');
      await prefs.remove('giant_pending_session_id');
      return;
    }

    final completedTools = _agentSteps.where((event) =>
      event['status'] == 'completed' &&
      (event['type'] == 'tool_output' || event['type'] == 'file_created' || event['type'] == 'file_updated')
    ).toList();
    final lastTool = completedTools.isEmpty ? null : completedTools.last;
    final rawToolResult = lastTool == null
        ? ''
        : (lastTool['output'] ?? lastTool['content'] ?? lastTool['file_name'] ?? '').toString();
    final toolContext = rawToolResult.isEmpty
        ? ''
        : '\\n\\nآخر نتيجة أداة محفوظة قبل الانقطاع:\\n${(rawToolResult.length > 1800 ? rawToolResult.substring(0, 1800) : rawToolResult)}';

    setState(() => _isLoading = true);
    try {
      final response = await _generateWithStages('${_contextualPrompt(pending)}$toolContext');
      await prefs.remove('giant_pending_task');
      await prefs.remove('giant_pending_session_id');
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

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    
    setState(() {
      _messages.add({
        'isUser': true,
        'content': text,
        'time': DateTime.now(),
      });
      _controller.clear();
      _isLoading = true;
    });
    await _saveMessage(text, true);
    final current = await _db?.query('sessions', columns: ['title'], where: 'id = ?', whereArgs: [_currentSessionId], limit: 1);
    if (current != null && current.isNotEmpty && current.first['title'] == 'جلسة جديدة') {
      final title = text.length > 36 ? '${text.substring(0, 36)}…' : text;
      await _db?.update('sessions', {'title': title, 'updated_at': DateTime.now().millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [_currentSessionId]);
      await _loadSessions();
    }
    final taskPrefs = await SharedPreferences.getInstance();
    await taskPrefs.setString('giant_pending_task', text);
    await taskPrefs.setString('giant_pending_session_id', _currentSessionId);
    _scrollToBottom();

    final response = await _generateWithStages(_contextualPrompt(text));
    await taskPrefs.remove('giant_pending_task');
    await taskPrefs.remove('giant_pending_session_id');

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
      final analysis = await FileUploadService.instance.processFile(file);
      final document = await file.readAsString();
      final boundedDocument = document.length > 40000
          ? '${document.substring(0, 40000)}\\n[تم اقتطاع بقية الملف لحماية نافذة السياق]'
          : document;
      final attachmentMessage = 'ملف مرفق: ${analysis['filename']}\\n'
          'النوع: ${analysis['extension']} • الحجم: ${analysis['size_bytes']} بايت\\n'
          'البيانات الأولية: ${jsonEncode(analysis)}';
      setState(() {
        _messages.add({
          'isUser': true,
          'content': attachmentMessage,
          'time': DateTime.now(),
        });
        _isLoading = true;
      });
      await _saveMessage(attachmentMessage, true);
      final response = await _generateWithStages(
        'حلّل محتوى الملف المرفق اعتماداً على النص الفعلي التالي. '
        'اذكر حدود التحليل ولا تخترع بيانات غير موجودة.\\n'
        'تحليل الملف: ${jsonEncode(analysis)}\\n'
        'محتوى الملف:\\n$boundedDocument',
      );
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
    setState(() {
      _messages.add({
        'isUser': true,
        'content': 'صورة مرفقة: ${image.name}',
        'time': DateTime.now(),
      });
      _isLoading = true;
    });
    await _saveMessage('صورة مرفقة: ${image.name}', true);
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
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      height: 46,
      child: Row(
        children: [
          Icon(icon, size: 19, color: const Color(0xFFB7C4C2)),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
        ],
      ),
    );
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

  bool _timelineExpanded = true;

  Widget _buildAgentTimeline() {
    if (_agentSteps.isEmpty) return const SizedBox.shrink();
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
            onTap: () => setState(() => _timelineExpanded = !_timelineExpanded),
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
                        Text('${_agentSteps.length} أحداث من المحرك',
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
                      builder: (_) => AgentWorkspaceScreen(steps: List<Map<String, dynamic>>.from(_agentSteps)),
                    )),
                  ),
                  Icon(_timelineExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: mutedColor, size: 20),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _timelineExpanded
                ? Column(
                    children: List.generate(_agentSteps.length, (index) {
                      final step = _agentSteps[index];
                      final status = step['status']?.toString() ?? 'completed';
                      final failed = status == 'failed' || status == 'interrupted';
                      final running = status == 'running' || status == 'pending';
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
                          : failed
                              ? 'فشل'
                              : status == 'interrupted'
                                  ? 'متوقف'
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
                                                ? const Color(0xFF54C7B7)
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
                                    ? SizedBox(
                                        key: const ValueKey('running'),
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: color),
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
          if (_timelineExpanded)
            const SizedBox(height: 7),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('Giant Agent X', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        actions: [
          if (_isLoading)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent),
              tooltip: 'إيقاف الوكيل',
              onPressed: _cancelAgent,
            ),
          PopupMenuButton<String>(
            tooltip: 'القائمة',
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: const Color(0xFF242424),
            elevation: 10,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Colors.white12),
            ),
            offset: const Offset(0, 8),
            constraints: const BoxConstraints(minWidth: 220),
            onSelected: (value) {
              switch (value) {
                case 'new':
                  _newConversation();
                  break;
                case 'export':
                  _exportWorkspace();
                  break;
                case 'refresh':
                  _refreshModels();
                  break;
                case 'history':
                  _clearHistory();
                  break;
                case 'workflow':
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AgentWorkflowScreen()),
                  );
                  break;
                case 'desktop':
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => AgentWorkspaceScreen(steps: List<Map<String, dynamic>>.from(_agentSteps))),
                  );
                  break;
                case 'settings':
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                  break;
              }
            },
            itemBuilder: (context) => [
              _menuItem('new', Icons.add_comment_outlined, 'محادثة جديدة'),
              _menuItem('workflow', Icons.account_tree_outlined, 'تنفيذ الوكيل'),
              _menuItem('desktop', Icons.desktop_windows_outlined, 'سطح المكتب'),
              _menuItem('export', Icons.archive_outlined, 'تصدير مساحة العمل'),
              const PopupMenuDivider(height: 8),
              _menuItem('refresh', Icons.refresh, 'تحديث النماذج'),
              _menuItem('history', Icons.history, 'مسح سجل المحادثات'),
              const PopupMenuDivider(height: 8),
              _menuItem('settings', Icons.settings_outlined, 'الإعدادات'),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            Container(
              height: 180,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.deepPurple.shade700, Colors.deepPurple.shade900],
                ),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bolt, size: 50, color: Colors.white),
                    SizedBox(height: 10),
                    Text(
                      'Giant Agent X',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'الوكيل العملاق',
                      style: TextStyle(fontSize: 14, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file, color: Colors.blue),
              title: const Text('استيراد نموذج'),
              subtitle: const Text('اختر نموذج GGUF من الهاتف'),
              onTap: () {
                Navigator.pop(context);
                _importModel();
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file, color: Colors.green),
              title: const Text('رفع ملف'),
              onTap: () {
                Navigator.pop(context);
                _pickFile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.image, color: Colors.orange),
              title: const Text('رفع صورة'),
              onTap: () {
                Navigator.pop(context);
                _pickImage();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.add_comment_outlined),
              title: const Text('جلسة جديدة'),
              onTap: () { Navigator.pop(context); _createNewSession(); },
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 6),
              child: Text('سجل المحادثات', style: Theme.of(context).textTheme.titleSmall),
            ),
            SizedBox(
              height: 220,
              child: ListView.builder(
                itemCount: _sessions.length,
                itemBuilder: (context, index) {
                  final session = _sessions[index];
                  return ListTile(
                    dense: true,
                    selected: session.id == _currentSessionId,
                    leading: const Icon(Icons.chat_bubble_outline, size: 18),
                    title: Text(session.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(session.updatedAt.toLocal().toString().substring(0, 16)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () => _deleteSession(session),
                    ),
                    onTap: () => _switchSession(session),
                  );
                },
              ),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
              title: const Text('مسح جميع الجلسات'),
              onTap: () { Navigator.pop(context); _clearAllSessions(); },
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'النماذج المتاحة',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _models.length,
                itemBuilder: (context, index) {
                  final model = _models[index];
                  final isActive = model['id'] == _activeModel['id'];
                  return ListTile(
                    leading: Icon(
                      isActive ? Icons.check_circle : Icons.circle_outlined,
                      color: isActive ? Colors.green : Colors.grey,
                    ),
                    title: Text(
                      model['name'],
                      style: TextStyle(fontWeight: isActive ? FontWeight.bold : FontWeight.normal),
                    ),
                    subtitle: Text('${model['size']} • ${model['type']}'),
                    trailing: isActive
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text('نشط', style: TextStyle(fontSize: 10, color: Colors.green)),
                          )
                        : null,
                    onTap: () => _switchModel(model),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: _modelService.hasActiveModel() ? const Color(0xFF18352F) : const Color(0xFF382B18),
            child: Row(
              children: [
                Icon(
                  _modelService.hasActiveModel() ? Icons.check_circle : Icons.warning,
                  size: 18,
                  color: _modelService.hasActiveModel() ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _modelService.hasActiveModel() 
                        ? 'النموذج: ${_modelService.getActiveModelName()}' 
                        : 'لا يوجد نموذج — افتح القائمة ثم اختر استيراد نموذج',
                    style: TextStyle(
                      fontSize: 13,
                      color: _modelService.hasActiveModel() ? Colors.green.shade200 : Colors.orange.shade200,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_agentSteps.isNotEmpty ? 1 : 0),
              itemBuilder: (context, index) {
                if (_agentSteps.isNotEmpty && index == 0) {
                  return _buildAgentTimeline();
                }
                final messageIndex = index - (_agentSteps.isNotEmpty ? 1 : 0);
                final msg = _messages[messageIndex];
                final isUser = msg['isUser'] as bool;
                return Align(
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
                        SelectableText(
                          msg['content'],
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
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
                );
              },
            ),
          ),
          if (_isLoading && _streamingResponse.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(14)),
              child: SelectableText(_streamingResponse, style: const TextStyle(color: Colors.white, fontSize: 14)),
            ),
          if (_isLoading)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _thinkingStage.isEmpty ? 'يعالج النموذج طلبك...' : _thinkingStage,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const Text('Giant AI', style: TextStyle(fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                ),
                const LinearProgressIndicator(),
              ],
            ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              border: const Border(top: BorderSide(color: Colors.white12)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  onPressed: _pickFile,
                  tooltip: 'رفع ملف',
                ),
                IconButton(
                  icon: const Icon(Icons.image),
                  onPressed: _pickImage,
                  tooltip: 'رفع صورة',
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: true,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                      hintText: 'اكتب رسالتك...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF2A2A2A),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: Colors.deepPurple,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
