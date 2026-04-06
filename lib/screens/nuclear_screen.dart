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
☢️ **GIANT AGENT X - NUCLEAR MODE** ☢️

💥 **أقوى وكيل في العالم!**

📊 **القدرات:**
• معالجة 10,000+ نص في الثانية
• قاعدة بيانات عملاقة
• إنشاء مواقع وأكواد
• تحليل ذكي
• رفع ملفات TXT/JSON/CSV

⚡ **الأوامر:**
• "أنشئ موقعاً" - إنشاء HTML
• "اكتب كود" - إنشاء كود
• "حلل نص: ..." - تحليل
• "5+3" - حساب
• "قاعدة بيانات" - الإحصائيات
• "رفع ملف" - معلومات الرفع

🔥 **ابدأ الآن!**
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('💀 GIANT AGENT X'),
        centerTitle: true,
        backgroundColor: Colors.deepPurple,
        actions: [
          IconButton(
            icon: const Icon(Icons.info),
            onPressed: () {
              _messages.add({
                'isUser': false,
                'content': _agent._databaseInfo(),
                'time': DateTime.now(),
              });
              _scrollToBottom();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // شريط الحالة
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.deepPurple.shade900,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('⚡ NUCLEAR MODE', style: TextStyle(fontSize: 10)),
                Text('💾 DB: ACTIVE', style: TextStyle(fontSize: 10)),
                Text('🚀 SPEED: MAX', style: TextStyle(fontSize: 10)),
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
                IconButton(
                  icon: const Icon(Icons.attach_file, color: Colors.white),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('📁 قريباً: رفع الملفات - تحديث قادم!')),
                    );
                  },
                ),
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
}
  String _databaseInfo() { return ''; }
