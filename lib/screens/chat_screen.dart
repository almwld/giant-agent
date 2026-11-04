import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import '../services/model_service.dart';
import 'agent_workspace_screen.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

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
  final Terminal _terminal = Terminal(maxLines: 5000);

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
      if (token.isNotEmpty) setState(() => _streamingResponse += token);
      _scrollToBottom();
      return;
    }
    final id = step['id']?.toString() ?? '';
    if (id.isEmpty) return;
    setState(() {
      final index = _agentSteps.indexWhere((item) => item['id'] == id);
      if (index >= 0) { _agentSteps[index] = step; } else { _agentSteps.add(step); }
      _thinkingStage = step['title']?.toString() ?? '';
    });
    _scrollToBottom();
  }

  Future<String> _generateWithStages(String prompt) async {
    if (mounted) setState(() { _agentSteps.clear(); _streamingResponse = ''; _thinkingStage = 'بانتظار أحداث المحرك المحلي...'; });
    try {
      return await _modelService.processInput(prompt);
    } finally {
      if (mounted) setState(() => _thinkingStage = '');
    }
  }
  List<Map<String, dynamic>> _models = [];
  Map<String, dynamic> _activeModel = {};
  Database? _db;

  @override
  void initState() {
    super.initState();
    _init();
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
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            content TEXT,
            isUser INTEGER,
            timestamp INTEGER
          )
        ''');
      },
    );
    await _loadHistory();
  }

  Future<void> _loadHistory() async {
    final messages = await _db?.query('messages', orderBy: 'timestamp ASC');
    if (messages != null && mounted) {
      setState(() {
        for (var msg in messages) {
          final int timestamp = msg['timestamp'] as int;
          _messages.add({
            'isUser': msg['isUser'] == 1,
            'content': msg['content'] as String,
            'time': DateTime.fromMillisecondsSinceEpoch(timestamp),
          });
        }
      });
      _scrollToBottom();
    }
  }

  Future<void> _saveMessage(String content, bool isUser) async {
    await _db?.insert('messages', {
      'content': content,
      'isUser': isUser ? 1 : 0,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
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
              await _db?.delete('messages');
              setState(() => _messages.clear());
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

  void _showTerminal() {
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
                const Expanded(child: Text('Python Terminal', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
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
        const SnackBar(content: Text('✅ تم استيراد النموذج بنجاح')),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ فشل استيراد النموذج')),
      );
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
    _scrollToBottom();

    final response = await _generateWithStages(text);

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
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null && mounted) {
      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      
      setState(() {
        _messages.add({
          'isUser': true,
          'content': '📁 ${result.files.single.name}\n${content.length > 500 ? content.substring(0, 500) + '...' : content}',
          'time': DateTime.now(),
        });
        _isLoading = true;
      });
      
      final response = await _generateWithStages('تحليل الملف: $content');
      
      setState(() {
        _messages.add({
          'isUser': false,
          'content': response,
          'time': DateTime.now(),
        });
        _isLoading = false;
      });
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image != null && mounted) {
      setState(() {
        _messages.add({
          'isUser': true,
          'content': '🖼️ ${image.name}',
          'time': DateTime.now(),
        });
        _isLoading = true;
      });
      
      final response = await _generateWithStages('تحليل الصورة: ${image.name}');
      
      setState(() {
        _messages.add({
          'isUser': false,
          'content': response,
          'time': DateTime.now(),
        });
        _isLoading = false;
      });
    }
  }

  void _newConversation() {
    setState(() {
      _messages.clear();
    });
  }

  void _switchModel(Map<String, dynamic> model) async {
    if (model['id'] == 'no_model') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ لا يوجد نموذج محدد')),
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

  IconData _agentStepIcon(String type) {
    switch (type) {
      case 'code':
      case 'tool_code': return Icons.code;
      case 'file':
      case 'file_created': return Icons.insert_drive_file_outlined;
      case 'terminal':
      case 'terminal_run': return Icons.terminal;
      case 'todo': return Icons.checklist;
      case 'thought': return Icons.psychology_alt_outlined;
      case 'tool_error': return Icons.error_outline;
      default: return Icons.circle_outlined;
    }
  }

  void _showAgentStep(Map<String, dynamic> step) {
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
            if (command != null) Padding(padding: const EdgeInsets.all(18), child: SelectableText('\\$ $command', style: const TextStyle(color: Colors.lightGreenAccent, fontFamily: 'monospace'))),
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

  Widget _buildAgentTimeline() {
    if (_agentSteps.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(color: Colors.grey.shade900, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.account_tree_outlined, color: Colors.tealAccent),
        title: const Text('سجل تنفيذ الوكيل', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text('${_agentSteps.length} أحداث من المحرك', style: const TextStyle(color: Colors.white60, fontSize: 11)),
        trailing: IconButton(
          tooltip: 'فتح مساحة عمل الوكيل',
          icon: const Icon(Icons.computer_outlined, color: Colors.tealAccent),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => AgentWorkspaceScreen(steps: List<Map<String, dynamic>>.from(_agentSteps)),
          )),
        ),
        children: _agentSteps.map((step) {
          final failed = step['status'] == 'failed';
          final running = step['status'] == 'running';
          final color = failed ? Colors.redAccent : (running ? Colors.orangeAccent : Colors.tealAccent);
          final type = step['type']?.toString() ?? 'thought';
          final icon = _agentStepIcon(type);
          final subtitle = step['subtitle']?.toString();
          final hasPreview = step['content'] != null || step['output'] != null ||
              step['command'] != null || step['details'] != null || step['file_name'] != null;
          return InkWell(
            onTap: hasPreview ? () => _showAgentStep(step) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 26, child: Column(children: [
                    Icon(icon, color: color, size: 18),
                    Container(width: 1, height: 24, color: Colors.white24),
                  ])),
                  const SizedBox(width: 9),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 7, children: [
                      Text(step['title']?.toString() ?? 'حدث', style: TextStyle(color: failed ? Colors.red.shade200 : Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                      if (subtitle != null && subtitle.isNotEmpty)
                        Text('| $subtitle', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    ]),
                    if (step['details'] != null)
                      Padding(padding: const EdgeInsets.only(top: 3), child: Text(step['details'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 11))),
                  ])),
                  if (hasPreview) const Icon(Icons.open_in_new, size: 14, color: Colors.white38),
                  const SizedBox(width: 5),
                  if (running) SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: color))
                  else Icon(failed ? Icons.error_outline : Icons.check_circle_outline, color: color, size: 16),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Giant Agent X'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.terminal),
            tooltip: 'Python Terminal',
            onPressed: _showTerminal,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshModels,
            tooltip: 'تحديث',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _newConversation,
            tooltip: 'جديد',
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: _clearHistory,
            tooltip: 'مسح المحادثات',
          ),
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
            color: _modelService.hasActiveModel() ? Colors.green.shade50 : Colors.orange.shade50,
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
                        : '⚠️ لا يوجد نموذج - اضغط ☰ ← استيراد نموذج',
                    style: TextStyle(
                      fontSize: 13,
                      color: _modelService.hasActiveModel() ? Colors.green.shade700 : Colors.orange.shade700,
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
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg['isUser'] as bool;
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.8,
                    ),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.deepPurple : Colors.grey.shade200,
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
                            color: isUser ? Colors.white : Colors.black87,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${(msg['time'] as DateTime).hour.toString().padLeft(2, '0')}:${(msg['time'] as DateTime).minute.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontSize: 10,
                            color: isUser ? Colors.white70 : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (_agentSteps.isNotEmpty) _buildAgentTimeline(),
          if (_isLoading && _streamingResponse.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(14)),
              child: SelectableText(_streamingResponse, style: const TextStyle(color: Colors.black87, fontSize: 14)),
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
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
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
                    decoration: InputDecoration(
                      hintText: 'اكتب رسالتك...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade100,
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
