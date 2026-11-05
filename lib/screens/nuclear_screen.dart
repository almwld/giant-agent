import 'package:flutter/material.dart';
import '../agent/task_manager.dart';
import '../services/file_upload_service.dart';
import '../services/model_service.dart';
import '../widgets/status_bar.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/quick_actions.dart';
import '../widgets/thinking_indicator.dart';
import '../widgets/model_selector.dart';

class NuclearScreen extends StatefulWidget {
  const NuclearScreen({super.key});

  @override
  State<NuclearScreen> createState() => _NuclearScreenState();
}

class _NuclearScreenState extends State<NuclearScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  final ScrollController _scrollController = ScrollController();
  final ModelService _models = ModelService();
  final FileUploadService _files = FileUploadService.instance;

  bool _isLoading = false;
  String _thinkingMessage = 'جاري تنفيذ المهمة';
  int _processedFiles = 0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _files.init();
      await _models.refreshModels();
      final history = await _files.getHistory();
      if (!mounted) return;
      setState(() {
        _processedFiles = history.length;
        _addWelcomeMessage();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _addWelcomeMessage();
        _messages.add({
          'isUser': false,
          'content': 'تعذر تهيئة خدمات الملفات أو النماذج: $error',
          'time': DateTime.now(),
        });
      });
    }
    await _resumePausedTask();
  }

  Future<void> _resumePausedTask() async {
    final manager = TaskManager();
    final recoverable = (await manager.getTasksForConversation('nuclear'))
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
        title: const Text('مهمة غير مكتملة'),
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

    setState(() {
      _isLoading = true;
      _thinkingMessage = 'استئناف المهمة المحفوظة...';
    });
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
      _thinkingMessage = 'جاري تنفيذ المهمة';
    });
    _scrollToBottom();
    if (continueRecovery) await _resumePausedTask();
  }

  void _addWelcomeMessage() {
    final activeModel = _models.getActiveModel();
    _messages.add({
      'isUser': false,
      'content': '''
**GIANT AGENT**

النموذج المحلي: ${activeModel['name']}

يمكنك تنفيذ المهام من خلال المحرك المحلي، أو اختيار ملف لتحليله وحفظه في سجل الملفات.

الأدوات المتاحة تعتمد على النموذج المحلي وواجهات التنفيذ المفعّلة.
''',
      'time': DateTime.now(),
    });
  }

  Future<void> _uploadFile() async {
    if (_isLoading) return;
    try {
      final file = await _files.pickFile();
      if (file == null) return;
      if (!mounted) return;

      setState(() {
        _isLoading = true;
        _thinkingMessage = 'جارٍ تحليل الملف';
        _messages.add({
          'isUser': true,
          'content': 'ملف: ${file.uri.pathSegments.last}',
          'time': DateTime.now(),
        });
      });

      final result = await _files.processFile(file);
      final extracted = result['extracted_text']?.toString() ?? '';
      final summary = StringBuffer()
        ..writeln('تمت معالجة الملف وحفظه في السجل.')
        ..writeln('الاسم: ${result['filename']}')
        ..writeln('النوع: ${result['extension']}')
        ..writeln('الحجم: ${result['size_bytes']} بايت')
        ..writeln('الأسطر: ${result['lines']}')
        ..writeln('الكلمات: ${result['words']}')
        ..writeln('الأحرف المستخرجة: ${result['characters']}');

      if (extracted.isNotEmpty) {
        summary
          ..writeln()
          ..writeln('مقتطف من المحتوى:')
          ..writeln(extracted.length > 1800 ? extracted.substring(0, 1800) : extracted);
      }

      final history = await _files.getHistory();
      if (!mounted) return;
      setState(() {
        _processedFiles = history.length;
        _messages.add({
          'isUser': false,
          'content': summary.toString(),
          'time': DateTime.now(),
        });
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.add({
          'isUser': false,
          'content': 'تعذرت معالجة الملف: $error',
          'time': DateTime.now(),
        });
        _isLoading = false;
      });
    }
  }

  Future<void> _sendMessage() async {
    final prompt = _controller.text.trim();
    if (prompt.isEmpty || _isLoading) return;

    setState(() {
      _messages.add({
        'isUser': true,
        'content': prompt,
        'time': DateTime.now(),
      });
      _controller.clear();
      _isLoading = true;
      _thinkingMessage = 'جارٍ تنفيذ الطلب عبر النموذج المحلي';
    });
    _scrollToBottom();

    String response;
    try {
      await TaskManager().createTask(prompt, conversationId: 'nuclear');
      final execution = await TaskManager().executeNextStep();
      response = {'completed', 'paused'}.contains(execution['status'])
          ? execution['result']?.toString() ?? ''
          : 'تعذر إكمال الطلب: ${execution['error'] ?? execution['status']}';
    } catch (error) {
      response = 'تعذر إكمال الطلب: $error';
    }

    if (!mounted) return;
    setState(() {
      _messages.add({
        'isUser': false,
        'content': response,
        'time': DateTime.now(),
      });
      _isLoading = false;
    });
    _scrollToBottom();
  }

  Future<void> _showModels() async {
    await _models.refreshModels();
    if (!mounted) return;
    final models = _models.getModels();
    final active = _models.getActiveModel();
    final lines = models.map((model) {
      final marker = model['id'] == active['id'] ? '✓' : '•';
      return '$marker ${model['name']} — ${model['size']}';
    }).join('\n');
    setState(() {
      _messages.add({
        'isUser': false,
        'content': lines.isEmpty ? 'لم يتم العثور على نماذج GGUF.' : 'النماذج المحلية:\n$lines',
        'time': DateTime.now(),
      });
    });
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

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeModel = _models.getActiveModel();
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Giant Agent'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.model_training),
            onPressed: _showModels,
            tooltip: 'النماذج المتاحة',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: ModelSelector(
            onModelChanged: () {
              if (mounted) setState(() {});
            },
          ),
        ),
      ),
      body: Column(
        children: [
          StatusBar(
            modelName: activeModel['name']?.toString() ?? 'لا يوجد',
            processedFiles: _processedFiles,
            speed: _models.isBusy ? 'BUSY' : 'READY',
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return ChatBubble(
                  isUser: message['isUser'] as bool,
                  message: message['content'] as String,
                  time: message['time'] as DateTime,
                );
              },
            ),
          ),
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.all(8),
              child: ThinkingIndicator(message: _thinkingMessage),
            ),
          QuickActions(
            onTap: (command) {
              _controller.text = command;
              _sendMessage();
            },
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _isLoading ? null : _uploadFile,
                    icon: const Icon(Icons.attach_file),
                    tooltip: 'تحليل ملف',
                  ),
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
