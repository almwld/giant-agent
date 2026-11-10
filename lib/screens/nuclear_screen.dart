import 'package:flutter/material.dart';
import '../services/agent_service.dart';

class NuclearScreen extends StatefulWidget {
  const NuclearScreen({super.key});

  @override
  State<NuclearScreen> createState() => _NuclearScreenState();
}

class _NuclearScreenState extends State<NuclearScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  final ScrollController _scrollController = ScrollController();
  final AgentService _agent = AgentService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _addWelcomeMessage();
  }

  void _addWelcomeMessage() {
    _messages.add({
      'isUser': false,
      'content': '''
⚡ **GIANT AGENT X - أقوى وكيل في العالم** ⚡

🧠 **8 وكلاء متخصصين يعملون معاً!**

⚡ **الأوامر السريعة:**

• `جميع الوكلاء` - تشغيل الـ8 وكلاء معاً
• `المحلل [نص]` - تحليل النص
• `المبرمج [طلب]` - توليد كود
• `المبدع [موضوع]` - كتابة إبداعية
• `إحصائيات` - عرض إحصائيات الفريق
• `مرحبا` - ترحيب
• `موقع` - إنشاء موقع HTML
• `كود` - إنشاء كود

🔥 **ابدأ الآن!** اكتب أمراً أو استخدم الأزرار أدناه.
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
    });
    _scrollToBottom();

    final response = await _agent.process(text);

    setState(() {
      _messages.add({'isUser': false, 'content': response, 'time': DateTime.now()});
      _isLoading = false;
    });
    _scrollToBottom();
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

  void _runAllAgents() {
    _controller.text = 'جميع الوكلاء';
    _sendMessage();
  }

  void _runAnalyst() {
    _controller.text = 'المحلل الذكاء الاصطناعي';
    _sendMessage();
  }

  void _runCoder() {
    _controller.text = 'المبرمج حساب المتوسط';
    _sendMessage();
  }

  void _runCreator() {
    _controller.text = 'المبدع الإبداع';
    _sendMessage();
  }

  void _showStats() {
    _controller.text = 'إحصائيات';
    _sendMessage();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('💀 GIANT AGENT X'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics),
            onPressed: _showStats,
            tooltip: 'إحصائيات',
          ),
        ],
      ),
      body: Column(
        children: [
          // أزرار الوكلاء السريعة
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildQuickButton('🧠', 'الكل', _runAllAgents, Colors.deepPurple),
                _buildQuickButton('🔍', 'محلل', _runAnalyst, Colors.blue),
                _buildQuickButton('💻', 'مبرمج', _runCoder, Colors.green),
                _buildQuickButton('🎨', 'مبدع', _runCreator, Colors.orange),
                _buildQuickButton('📊', 'إحصائيات', _showStats, Colors.teal),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg['isUser'] as bool;
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.85,
                    ),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.deepPurple : Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: SelectableText(
                      msg['content'],
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: LinearProgressIndicator(),
            ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              border: Border(top: BorderSide(color: Colors.deepPurple)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'اكتب أمراً...',
                      hintStyle: TextStyle(color: Colors.grey.shade500),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade800,
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

  Widget _buildQuickButton(String icon, String label, VoidCallback onTap, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        elevation: 2,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color.withOpacity(0.3), color.withOpacity(0.1)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withOpacity(0.5)),
            ),
            child: Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(fontSize: 13, color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
