import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import '../services/model_service.dart';
import '../features/assistant/application/assistant_factory.dart';
import '../features/assistant/application/chat_controller.dart';
import '../features/assistant/application/gateway_settings.dart';
import '../features/assistant/domain/chat_attachment.dart';
import '../features/assistant/domain/chat_message.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, dynamic>> _legacyMessages = [];
  final List<Map<String, dynamic>> _messages = [];
  final ScrollController _scrollController = ScrollController();
  final ModelService _modelService = ModelService();
  final GatewaySettings _settings = GatewaySettings();

  ChatController? _chat;
  bool _isLoading = false;
  bool _gatewayConfigured = false;
  bool _initializing = true;
  List<Map<String, dynamic>> _models = [];
  Map<String, dynamic> _activeModel = {};
  Database? _db;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _initDatabase();
    await _modelService.init();
    _chat = AssistantFactory.create(settings: _settings);
    _chat!.addListener(_syncChatState);
    await _chat!.initialize();
    _gatewayConfigured = await _settings.isConfigured;
    if (!mounted) return;
    setState(() {
      _models = _modelService.getModels();
      _activeModel = _modelService.getActiveModel();
      _initializing = false;
    });
    _syncChatState();
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
    final rows = await _db!.query('messages', orderBy: 'timestamp ASC');
    _legacyMessages.addAll(rows.map((msg) => {
      'isUser': msg['isUser'] == 1,
      'content': msg['content'] as String? ?? '',
      'time': DateTime.fromMillisecondsSinceEpoch(msg['timestamp'] as int),
    }));
    _rebuildMessages();
  }

  void _rebuildMessages() {
    _messages
      ..clear()
      ..addAll(_legacyMessages)
      ..addAll((_chat?.messages ?? const <ChatMessage>[]).map(_toUiMessage));
  }

  Map<String, dynamic> _toUiMessage(ChatMessage message) => {
    'isUser': message.role == MessageRole.user,
    'content': message.content.isEmpty && message.status == MessageStatus.streaming
        ? 'يكتب الآن…'
        : message.content,
    'time': message.createdAt,
    'status': message.status,
    'error': message.error,
  };

  void _syncChatState() {
    if (!mounted || _chat == null) return;
    setState(() {
      _isLoading = _chat!.isGenerating;
      _rebuildMessages();
    });
    _scrollToBottom();
  }

  Future<void> _refreshModels() async {
    await _modelService.refreshModels();
    if (!mounted) return;
    setState(() {
      _models = _modelService.getModels();
      _activeModel = _modelService.getActiveModel();
    });
  }

  Future<void> _importModel() async {
    final success = await _modelService.importModelFromFile();
    if (!mounted) return;
    if (success) await _refreshModels();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(success ? 'تم استيراد ملف النموذج.' : 'تعذر استيراد النموذج.'),
    ));
  }

  Future<void> _configureGateway() async {
    final urlController = TextEditingController(text: await _settings.baseUrl);
    final tokenController = TextEditingController();
    final modelController = TextEditingController(
      text: await _settings.model ?? 'openrouter/free',
    );
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('اتصال الذكاء الاصطناعي'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'أدخل عنوان خادم Giant Agent ورمز الوصول الذي أعددته على الخادم. '
                'لا تضع مفتاح OpenAI أو OpenRouter هنا.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: urlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Gateway URL',
                  hintText: 'https://your-service.run.app',
                ),
              ),
              TextField(
                controller: tokenController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Gateway access token'),
              ),
              TextField(
                controller: modelController,
                decoration: const InputDecoration(
                  labelText: 'Model ID',
                  hintText: 'openrouter/free',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await _settings.save(
                  url: urlController.text,
                  token: tokenController.text,
                  model: modelController.text,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext, true);
              } catch (error) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text(error.toString())),
                  );
                }
              }
            },
            child: const Text('حفظ الاتصال'),
          ),
        ],
      ),
    );
    urlController.dispose();
    tokenController.dispose();
    modelController.dispose();
    if (saved == true && mounted) {
      setState(() => _gatewayConfigured = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ إعدادات الاتصال بأمان على الجهاز.')),
      );
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading || _chat == null) return;
    if (!_gatewayConfigured) {
      await _configureGateway();
      if (!_gatewayConfigured) return;
    }
    _controller.clear();
    await _chat!.send(text);
    if (mounted && _chat!.lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر الحصول على رد: ${_chat!.lastError}')),
      );
    }
  }

  String _mimeType(String name) {
    switch (name.split('.').last.toLowerCase()) {
      case 'png': return 'image/png';
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      case 'webp': return 'image/webp';
      case 'gif': return 'image/gif';
      case 'json': return 'application/json';
      case 'txt':
      case 'md':
      case 'csv':
      case 'log': return 'text/plain';
      default: return 'application/octet-stream';
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'md', 'csv', 'json', 'log'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || _chat == null) return;
    final picked = result.files.single;
    final bytes = picked.bytes ??
        (picked.path == null ? null : await File(picked.path!).readAsBytes());
    if (bytes == null) {
      _showMessage('تعذر قراءة الملف المحدد.');
      return;
    }
    try {
      final attachment = ChatAttachment(
        name: picked.name,
        mimeType: _mimeType(picked.name),
        bytes: bytes,
      );
      await _sendAttachment(attachment, 'حلّل الملف المرفق واشرح محتواه.');
    } catch (error) {
      _showMessage(error.toString());
    }
  }

  Future<void> _pickImage() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null || _chat == null) return;
    final bytes = await image.readAsBytes();
    final extension = image.name.split('.').last.toLowerCase();
    final mime = extension == 'png' ? 'image/png' :
        extension == 'webp' ? 'image/webp' : 'image/jpeg';
    await _sendAttachment(
      ChatAttachment(name: image.name, mimeType: mime, bytes: bytes),
      'حلّل الصورة المرفقة بالتفصيل.',
    );
  }

  Future<void> _sendAttachment(ChatAttachment attachment, String prompt) async {
    if (_isLoading) return;
    if (attachment.sizeInBytes > 10 * 1024 * 1024) {
      _showMessage('حجم الملف يتجاوز الحد المسموح به وهو 10 ميغابايت.');
      return;
    }
    if (!_gatewayConfigured) {
      await _configureGateway();
      if (!_gatewayConfigured) return;
    }
    await _chat!.send(prompt, attachments: [attachment]);
    if (mounted && _chat!.lastError != null) _showMessage(_chat!.lastError!);
  }

  Future<void> _newConversation() async {
    await _chat?.createConversation();
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مسح المحادثات'),
        content: const Text('سيتم حذف سجل المحادثة الحالي والرسائل القديمة المحفوظة على هذا الجهاز.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('مسح')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _db?.delete('messages');
    _legacyMessages.clear();
    await _chat?.deleteActiveConversation();
    _rebuildMessages();
    if (mounted) setState(() {});
  }

  Future<void> _openConversation(String id) async {
    await _chat?.openConversation(id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _switchModel(Map<String, dynamic> model) async {
    if (model['id'] == 'no_model') return;
    final success = await _modelService.switchModel(model['id']);
    if (!mounted) return;
    if (success) {
      setState(() => _activeModel = _modelService.getActiveModel());
      Navigator.pop(context);
      _showMessage('تم اختيار ملف النموذج المحلي. يلزم محرك استدلال متوافق لتشغيله.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _chat?.removeListener(_syncChatState);
    _chat?.dispose();
    _controller.dispose();
    _scrollController.dispose();
    _db?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Giant Agent X'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(_gatewayConfigured ? Icons.cloud_done : Icons.cloud_off),
            tooltip: 'إعداد اتصال الذكاء الاصطناعي',
            onPressed: _configureGateway,
          ),
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'محادثة جديدة',
            onPressed: _newConversation,
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'مسح السجل',
            onPressed: _clearHistory,
          ),
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            Container(
              height: 170,
              width: double.infinity,
              color: const Color(0xFF5146C8),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bolt, size: 48, color: Colors.white),
                    SizedBox(height: 8),
                    Text('Giant Agent X', style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white,
                    )),
                    Text('الوكيل العملاق', style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('إعداد اتصال AI'),
              subtitle: const Text('OpenRouter / Gemini / OpenAI عبر الخادم'),
              onTap: () { Navigator.pop(context); _configureGateway(); },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('استيراد نموذج محلي'),
              subtitle: const Text('إضافة ملف نموذج إلى الجهاز'),
              onTap: () { Navigator.pop(context); _importModel(); },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('إرفاق ملف نصي'),
              onTap: () { Navigator.pop(context); _pickFile(); },
            ),
            ListTile(
              leading: const Icon(Icons.image),
              title: const Text('إرفاق صورة'),
              onTap: () { Navigator.pop(context); _pickImage(); },
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(alignment: Alignment.centerLeft, child: Text(
                'المحادثات السابقة', style: TextStyle(fontWeight: FontWeight.bold),
              )),
            ),
            if ((_chat?.conversations ?? []).isNotEmpty)
              SizedBox(
                height: 190,
                child: ListView.builder(
                  itemCount: _chat!.conversations.length,
                  itemBuilder: (context, index) {
                    final conversation = _chat!.conversations[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.chat_bubble_outline, size: 18),
                      title: Text(conversation.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      selected: conversation.id == _chat!.activeConversationId,
                      onTap: () => _openConversation(conversation.id),
                    );
                  },
                ),
              ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Align(alignment: Alignment.centerLeft, child: Text(
                'النماذج المحلية الموجودة',
                style: TextStyle(fontWeight: FontWeight.bold),
              )),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _models.length,
                itemBuilder: (context, index) {
                  final model = _models[index];
                  final active = model['id'] == _activeModel['id'];
                  return ListTile(
                    leading: Icon(active ? Icons.check_circle : Icons.memory,
                        color: active ? Colors.green : null),
                    title: Text(model['name']?.toString() ?? 'Model'),
                    subtitle: Text('${model['size']} MB • ${model['type']}'),
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
          Material(
            color: _gatewayConfigured ? Colors.green.shade50 : Colors.orange.shade50,
            child: InkWell(
              onTap: _configureGateway,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(_gatewayConfigured ? Icons.cloud_done : Icons.cloud_off,
                        size: 18, color: _gatewayConfigured ? Colors.green : Colors.orange),
                    const SizedBox(width: 9),
                    Expanded(child: Text(
                      _initializing ? 'جارٍ تهيئة المساعد…' :
                      _gatewayConfigured ? 'تم إعداد اتصال بوابة الذكاء الاصطناعي' :
                      'اضغط هنا لإعداد اتصال الذكاء الاصطناعي',
                      style: TextStyle(fontSize: 13,
                        color: _gatewayConfigured ? Colors.green.shade800 : Colors.orange.shade900),
                    )),
                    const Icon(Icons.settings, size: 17),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _initializing
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(child: Text('مرحباً بك في Giant Agent\nكيف يمكنني مساعدتك؟',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 18)))
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isUser = msg['isUser'] as bool;
                          final status = msg['status'] as MessageStatus?;
                          return Align(
                            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .84),
                              decoration: BoxDecoration(
                                color: isUser ? const Color(0xFF5146C8) : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(17),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SelectableText(msg['content']?.toString() ?? '',
                                    style: TextStyle(color: isUser ? Colors.white : Colors.black87, fontSize: 14)),
                                  if (status == MessageStatus.failed) ...[
                                    const SizedBox(height: 6),
                                    Text('تعذر إكمال الرد', style: TextStyle(color: Colors.red.shade700, fontSize: 11)),
                                  ],
                                  const SizedBox(height: 4),
                                  Text(
                                    '${(msg['time'] as DateTime).hour.toString().padLeft(2, '0')}:${(msg['time'] as DateTime).minute.toString().padLeft(2, '0')}',
                                    style: TextStyle(fontSize: 10, color: isUser ? Colors.white70 : Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          if (_isLoading) const LinearProgressIndicator(minHeight: 2),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.add), onPressed: _pickFile, tooltip: 'إرفاق ملف'),
                  IconButton(icon: const Icon(Icons.image_outlined), onPressed: _pickImage, tooltip: 'إرفاق صورة'),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_isLoading,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      decoration: InputDecoration(
                        hintText: 'اسأل Giant Agent…',
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    onPressed: _isLoading ? () => _chat?.cancelGeneration() : _sendMessage,
                    icon: Icon(_isLoading ? Icons.stop : Icons.arrow_upward),
                    tooltip: _isLoading ? 'إيقاف التوليد' : 'إرسال',
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
