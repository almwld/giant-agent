import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
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
☢️ **NUCLEAR GIANT AGENT - THE ULTIMATE DESTROYER** ☢️

💥 **Nuclear Capabilities:**

| Command | Effect |
|---------|--------|
| `معالجة 1000 نص` | Process 1000 texts instantly |
| `معالجة 10000 نص` | Process 10000 texts at light speed |
| `توليد كود بايثون` | Generate nuclear-grade Python code |
| `تحليل متقدم [نص]` | Deep analysis with 99.99% accuracy |

🏆 **Performance Metrics:**
• Speed: 10,000 texts/sec
• Accuracy: 99.99%
• Power: MAXIMUM
• Status: ALL COMPETITORS DESTROYED

🔥 **Ready to annihilate? Type your command!**
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
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning, color: Colors.yellow),
            SizedBox(width: 8),
            Text('NUCLEAR AGENT'),
            SizedBox(width: 8),
            Icon(Icons.warning, color: Colors.yellow),
          ],
        ),
        backgroundColor: Colors.red.shade900,
      ),
      body: Column(
        children: [
          // شريط الطاقة النووية
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.red.shade900.withOpacity(0.5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('⚡ NUCLEAR POWER: 100%', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                Text('🔥 STATUS: CRITICAL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                Text('💀 MODE: DESTROY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
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
                      color: isUser ? Colors.red.shade900 : Colors.grey.shade900,
                      borderRadius: BorderRadius.circular(16),
                      border: isUser ? null : Border.all(color: Colors.red.shade900, width: 1),
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
            Container(
              padding: const EdgeInsets.all(8),
              child: const LinearProgressIndicator(
                backgroundColor: Colors.grey,
                color: Colors.red,
              ),
            ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              border: Border(top: BorderSide(color: Colors.red.shade900)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: '☢️ Enter nuclear command...',
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
                    decoration: BoxDecoration(
                      color: Colors.red.shade900,
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
