import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../services/agent_service.dart';
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
  final AgentService _agent = AgentService();
  bool _isLoading = false;
  bool _showThinking = false;
  String _thinkingText = '';

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _addWelcomeMessage();
  }

  Future<void> _loadMessages() async {
    final messages = await DatabaseService.getMessages();
    setState(() {
      _messages.clear();
      _messages.addAll(messages);
    });
  }

  void _addWelcomeMessage() {
    _messages.add({
      'isUser': false,
      'content': '''
🧠 **مرحباً بك في الوكيل العملاق!**

أنا وكيل ذكاء اصطناعي متطور يمكنني:

📁 **إنشاء الملفات** - نصوص، HTML، JSON
💻 **كتابة الأكواد** - Python, Dart, JavaScript
🌐 **إنشاء المواقع** - صفحات HTML كاملة
📊 **تحليل البيانات** - نصوص، أرقام، إحصائيات
🔢 **العمليات الحسابية** - جمع، طرح، ضرب، قسمة
⏰ **التذكيرات** - جدولة وتنبيهات
📝 **قوائم المهام** - تنظيم وإدارة
🌍 **الترجمة** - نصوص متعددة اللغات

**جرب هذه الأوامر:**
• `أنشئ موقعاً عن الذكاء الاصطناعي`
• `اكتب كود Python لحساب المتوسط`
• `حلل هذا النص: ...`
• `5+3×2`
• `ذكرني بموعد الساعة 5`

**ماذا تريد أن نفعل اليوم؟** 🚀
''',
      'time': DateTime.now(),
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({'isUser': true, 'content': text, 'time': DateTime.now()});
      _controller.clear();
      _isLoading = true;
      _showThinking = true;
      _thinkingText = '🧠 جاري التفكير...';
    });
    _scrollToBottom();

    await DatabaseService.saveMessage(text, true);

    // محاكاة التفكير
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() {
      _thinkingText = '⚙️ جاري تنفيذ المهمة...';
    });

    final response = await _agent.process(text);

    setState(() {
      _messages.add({'isUser': false, 'content': response, 'time': DateTime.now()});
      _isLoading = false;
      _showThinking = false;
    });
    _scrollToBottom();

    await DatabaseService.saveMessage(response, false);
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

  Future<void> _clearChat() async {
    await DatabaseService.clearMessages();
    setState(() {
      _messages.clear();
      _addWelcomeMessage();
    });
  }

  Future<void> _shareChat() async {
    final content = await DatabaseService.exportChat();
    await Share.share(content, subject: 'محادثة Giant Agent');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🧠 Giant Agent'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _shareChat,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _clearChat,
          ),
        ],
      ),
      body: Column(
        children: [
          // الأزرار السريعة
          QuickActions(onTap: (text) {
            _controller.text = text;
            _sendMessage();
          }),
          // منطقة المحادثة
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return MessageBubble(
                  isUser: msg['isUser'],
                  content: msg['content'],
                  time: msg['time'],
                );
              },
            ),
          ),
          // مؤشر التفكير
          if (_showThinking)
            Container(
              padding: const EdgeInsets.all(8),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(_thinkingText, style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          // شريط الإدخال
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              border: Border(top: BorderSide(color: Colors.grey.shade800)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'اكتب أمراً أو سؤالاً...',
                      hintStyle: TextStyle(color: Colors.grey.shade500),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF2D2D2D),
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
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF),
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
