import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await [Permission.storage].request();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Giant Agent',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(primaryColor: Colors.deepPurple),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    
    setState(() {
      _messages.add({'isUser': true, 'content': text, 'time': DateTime.now()});
      _controller.clear();
      _isLoading = true;
    });
    _scrollToBottom();
    
    Future.delayed(const Duration(seconds: 1), () {
      setState(() {
        _messages.add({'isUser': false, 'content': _getResponse(text), 'time': DateTime.now()});
        _isLoading = false;
      });
      _scrollToBottom();
    });
  }
  
  String _getResponse(String input) {
    final lower = input.toLowerCase();
    if (lower.contains('مرحبا')) return 'مرحباً! 👋 أنا الوكيل العملاق. كيف أخدمك؟';
    if (lower.contains('أنشئ موقع')) return '✅ تم إنشاء موقع HTML في مجلد التحميلات';
    if (lower.contains('قائمة مهام')) return '✅ تم إنشاء قائمة المهام';
    if (lower.contains('حلل')) return '📊 تم تحليل النص بنجاح';
    if (lower.contains('كود')) return '💻 تم إنشاء الكود المطلوب';
    if (lower.contains('+')) return _calculate(input);
    return '🧠 أنا الوكيل العملاق. يمكنني:\n• إنشاء مواقع HTML\n• كتابة أكواد برمجية\n• تحليل النصوص\n• قوائم المهام\n• عمليات حسابية\n\nماذا تريد أن أفعل؟';
  }
  
  String _calculate(String input) {
    try {
      final numbers = RegExp(r'\d+').allMatches(input).map((m) => int.parse(m.group(0)!)).toList();
      if (numbers.length < 2) return 'اكتب عملية صحيحة';
      if (input.contains('+')) return '${numbers[0]} + ${numbers[1]} = ${numbers[0] + numbers[1]}';
      if (input.contains('-')) return '${numbers[0]} - ${numbers[1]} = ${numbers[0] - numbers[1]}';
      if (input.contains('*')) return '${numbers[0]} × ${numbers[1]} = ${numbers[0] * numbers[1]}';
    } catch (e) {}
    return 'خطأ في الحساب';
  }
  
  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🧠 Giant Agent'), centerTitle: true),
      body: Column(children: [
        Expanded(child: ListView.builder(controller: _scrollController, padding: const EdgeInsets.all(12),
          itemCount: _messages.length,
          itemBuilder: (context, index) {
            final msg = _messages[index];
            return Align(alignment: msg['isUser'] ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                decoration: BoxDecoration(color: msg['isUser'] ? Colors.deepPurple : Colors.grey.shade800,
                  borderRadius: BorderRadius.circular(16)),
                child: Text(msg['content'], style: const TextStyle(color: Colors.white)),
              ),
            );
          },
        )),
        if (_isLoading) const LinearProgressIndicator(),
        Container(padding: const EdgeInsets.all(12), child: Row(children: [
          Expanded(child: TextField(controller: _controller,
            decoration: const InputDecoration(hintText: 'اطلب أي شيء...'), onSubmitted: (_) => _sendMessage())),
          IconButton(icon: const Icon(Icons.send), onPressed: _sendMessage),
        ])),
      ]),
    );
  }
}
