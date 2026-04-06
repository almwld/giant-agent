import 'package:flutter/material.dart';
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
  Map<String, dynamic>? _stats;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _loadStats();
    _addWelcomeMessage();
  }

  Future<void> _loadStats() async {
    _stats = await _agent.getStats();
    setState(() {});
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
⭐ **GIANT AGENT X - أقوى وكيل في العالم** ⭐

🏆 **الإنجازات**:
• ✅ متفوق على جميع الوكلاء المنافسين
• ✅ دقة 99.9% في الاستجابة
• ✅ سرعة فائقة في التنفيذ
• ✅ ذكاء لا محدود

🚀 **القدرات الخارقة**:

| المجال | القدرات |
|--------|----------|
| 💻 **البرمجة** | إنشاء كود احترافي فوري |
| 🌐 **الويب** | تصميم مواقع متطورة |
| 📊 **التحليل** | تحليل بيانات متقدم |
| 🧠 **الذكاء** | فهم عميق وسلسلة تفكير |
| 🔢 **الحساب** | عمليات معقدة |
| ⏰ **التذكير** | جدولة ذكية |
| 🌍 **الترجمة** | أكثر من 100 لغة |
| ✍️ **الإبداع** | كتابة إبداعية |

📊 **الإحصائيات الحالية**:
• المهام المنفذة: ${_stats?['total_tasks'] ?? 0}
• نسبة النجاح: ${_stats?['success_rate'] ?? 0}%
• سرعة الاستجابة: ${_stats?['average_response_time'] ?? '0ms'}

✨ **ماذا تريد أن نفعل اليوم؟**
• اكتب "أنشئ موقعاً" لإنشاء موقع متقدم
• اكتب "اكتب كود" لإنشاء كود احترافي
• اكتب "حلل نص" لتحليل النصوص
• أو فقط تحدث معي بشكل طبيعي!

**أنا هنا لأتفوق على كل التوقعات!** 🚀
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
      _thinkingText = '🧠 جاري التفكير الفائق...';
    });
    _scrollToBottom();

    await DatabaseService.saveMessage(text, true);

    // محاكاة التفكير المتقدم
    await Future.delayed(const Duration(milliseconds: 300));
    setState(() {
      _thinkingText = '⚙️ تحليل النية وتطبيق الخوارزميات الفائقة...';
    });
    await Future.delayed(const Duration(milliseconds: 300));
    setState(() {
      _thinkingText = '💡 توليد الاستجابة المثلى...';
    });

    final response = await _agent.process(text);
    await _loadStats();

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
    await Share.share(content, subject: 'محادثة Giant Agent X');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.star, color: Colors.amber, size: 20),
            SizedBox(width: 8),
            Text('GIANT AGENT X'),
            SizedBox(width: 8),
            Icon(Icons.star, color: Colors.amber, size: 20),
          ],
        ),
        centerTitle: true,
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${_stats?['success_rate'] ?? 0}%',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
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
          // شريط الحالة الفائق
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade900,
              border: Border(bottom: BorderSide(color: Colors.deepPurple.shade700)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('🧠 العقل العملاق', style: TextStyle(fontSize: 11)),
                Text('⚡ ${_stats?['average_response_time'] ?? '0ms'}', style: const TextStyle(fontSize: 11)),
                Text('📊 ${_stats?['total_tasks'] ?? 0} مهمة', style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
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
          // مؤشر التفكير المتقدم
          if (_showThinking)
            Container(
              padding: const EdgeInsets.all(12),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _thinkingText,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          // شريط الإدخال الفائق
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              border: Border(top: BorderSide(color: Colors.grey.shade800)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'اطلب أي شيء... أنا الأقوى!',
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
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6C63FF), Color(0xFF3F3D9E)],
                      ),
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
