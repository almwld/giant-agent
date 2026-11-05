import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../agent/task_manager.dart';
import '../services/database_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/quick_actions.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    try {
      final stored = await DatabaseService.getMessages();
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(stored.map((row) => {
                'isUser': row['isUser'] == 1,
                'content': row['text']?.toString() ?? '',
                'time': DateTime.fromMillisecondsSinceEpoch(
                  (row['timestamp'] as int?) ?? 0,
                ),
              }));
        if (_messages.isEmpty) _addWelcomeMessage();
      });
      _scrollToBottom();
      await _resumePausedTask();
    } catch (error) {
      if (!mounted) return;
      setState(_addWelcomeMessage);
    }
  }

  void _addWelcomeMessage() {
    _messages.add({
      'isUser': false,
      'content': '''
**مرحباً بك في Giant Agent**

وكيل محلي يعتمد على نموذج GGUF والأدوات المتاحة داخل التطبيق.

يمكنك طلب:
- إنشاء ملفات ومحتوى برمجي.
- قراءة الملفات وتحديثها داخل مساحة العمل.
- تنفيذ Python ضمن البيئة المحلية المقيّدة.
- تحليل الأسئلة والمهام متعددة الخطوات.

ابدأ بكتابة المهمة التي تريد تنفيذها.
''',
      'time': DateTime.now(),
    });
  }

  Future<void> _resumePausedTask() async {
    final manager = TaskManager();
    final recoverable = (await manager.getTasksForConversation('home'))
        .where((task) => {'paused', 'pending', 'failed'}.contains(task['status']))
        .toList(growable: false);
    if (recoverable.isEmpty || !mounted) return;
    final task = recoverable.last;
    final taskId = task['id'].toString();
    final description = task['description']?.toString() ?? 'مهمة محفوظة';
    final shouldResume = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('مهمة منزلية غير مكتملة'),
        content: Text('توقفت المهمة التالية قبل اكتمالها:\n$description\n\nهل تريد استئنافها؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء المهمة'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('استئناف'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (shouldResume != true) {
      await manager.markCancelled(taskId);
      return;
    }

    setState(() => _isLoading = true);
    String output;
    var continueRecovery = false;
    try {
      final result = await manager.resumeTask(taskId);
      continueRecovery = result['status'] == 'completed';
      output = result['result']?.toString() ??
          result['error']?.toString() ??
          'حالة المهمة: ${result['status']}';
    } catch (error) {
      output = 'تعذر استئناف المهمة: $error';
      await manager.markFailed(taskId, output);
    }
    if (!mounted) return;
    setState(() {
      _messages.add({'isUser': false, 'content': output, 'time': DateTime.now()});
      _isLoading = false;
    });
    await DatabaseService.saveMessage(output, false);
    _scrollToBottom();
    if (continueRecovery) await _resumePausedTask();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading) return;

    setState(() {
      _messages.add({'isUser': true, 'content': text, 'time': DateTime.now()});
      _controller.clear();
      _isLoading = true;
    });
    _scrollToBottom();

    await DatabaseService.saveMessage(text, true);
    String response;
    try {
      await TaskManager().createTask(text, conversationId: 'home');
      final execution = await TaskManager().executeNextStep();
      response = {'completed', 'paused'}.contains(execution['status'])
          ? execution['result']?.toString() ?? ''
          : 'تعذر إكمال الطلب: ${execution['error'] ?? execution['status']}';
    } catch (error) {
      response = 'تعذر إكمال الطلب: $error';
    }

    if (!mounted) return;
    setState(() {
      _messages.add({'isUser': false, 'content': response, 'time': DateTime.now()});
      _isLoading = false;
    });
    await DatabaseService.saveMessage(response, false);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _clearChat() async {
    await DatabaseService.clearMessages();
    if (!mounted) return;
    setState(() {
      _messages.clear();
      _addWelcomeMessage();
    });
  }

  Future<void> _shareChat() async {
    final content = await DatabaseService.exportToText();
    await Share.share(content);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Giant Agent'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          IconButton(icon: const Icon(Icons.share), onPressed: _shareChat),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _clearChat),
        ],
      ),
      body: Column(
        children: [
          QuickActions(
            onTap: (text) {
              _controller.text = text;
              _sendMessage();
            },
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return MessageBubble(
                  isUser: message['isUser'] as bool,
                  content: message['content'] as String,
                  time: message['time'] as DateTime,
                );
              },
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: LinearProgressIndicator(),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'اكتب مهمة أو سؤالاً...',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _isLoading ? null : _sendMessage,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
