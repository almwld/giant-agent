import 'dart:io';
import 'package:flutter/material.dart';
import '../services/agent_service.dart';
import '../services/file_upload_service.dart';
import '../services/model_service.dart';

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
    _initServices();
    _addWelcomeMessage();
  }

  Future<void> _initServices() async {
    await FileUploadService.initDB();
    await ModelService.getAvailableModels();
  }

  void _addWelcomeMessage() {
    final activeModel = ModelService.getActiveModel();
    _messages.add({
      'isUser': false,
      'content': '''
☢️ **GIANT AGENT X - NUCLEAR MODE** ☢️

🧠 **النموذج النشط**: ${activeModel['name']} v${activeModel['version']}

💥 **القدرات الخارقة:**
• 🧠 نماذج متعددة (TFLite)
• 📁 رفع ملفات (TXT/JSON/CSV)
• 🌐 إنشاء مواقع HTML
• 💻 كتابة أكواد برمجية
• 📊 تحليل النصوص الذكي
• 🔢 العمليات الحسابية

⚡ **الأوامر الرئيسية:**
• "النماذج" - عرض النماذج المتاحة
• "تبديل نموذج [الاسم]" - تبديل النموذج
• "رفع ملف" - تعليمات رفع الملفات
• "تاريخ الملفات" - عرض الملفات المرفوعة
• "أنشئ موقعاً" - إنشاء HTML
• "اكتب كود" - إنشاء كود

🔥 **ابدأ الآن!**
''',
      'time': DateTime.now(),
    });
  }

  Future<void> _uploadFile() async {
    final file = await FileUploadService.pickFile();
    if (file == null) return;
    
    setState(() {
      _isLoading = true;
      _messages.add({
        'isUser': true,
        'content': '📁 رفع ملف: ${file.path.split('/').last}',
        'time': DateTime.now(),
      });
    });
    _scrollToBottom();
    
    String response;
    final ext = file.path.split('.').last.toLowerCase();
    
    try {
      if (ext == 'txt') {
        final analysis = await FileUploadService.processTextFile(file);
        response = '''
✅ **تمت معالجة الملف النصي!**

📁 **الملف**: ${analysis['filename']}
📊 **الأسطر**: ${analysis['lines']}
📝 **الكلمات**: ${analysis['words']}
📏 **الحجم**: ${analysis['size']} بايت

💾 **تم حفظ الملف في قاعدة البيانات**
''';
      } else if (ext == 'json') {
        final analysis = await FileUploadService.processJsonFile(file);
        response = '''
✅ **تمت معالجة ملف JSON!**

📁 **الملف**: ${analysis['filename']}
🔑 **عدد المفاتيح**: ${analysis['keys']}
📏 **الحجم**: ${analysis['size']} بايت

💾 **تم حفظ الملف في قاعدة البيانات**
''';
      } else if (ext == 'csv') {
        final analysis = await FileUploadService.processCsvFile(file);
        response = '''
✅ **تمت معالجة ملف CSV!**

📁 **الملف**: ${analysis['filename']}
📊 **الصفوف**: ${analysis['rows']}
📐 **الأعمدة**: ${analysis['columns']}
📏 **الحجم**: ${analysis['size']} بايت

💾 **تم حفظ الملف في قاعدة البيانات**
''';
      } else if (ext == 'tflite') {
        final added = await ModelService.addCustomModel(file.path);
        if (added) {
          response = '''
✅ **تم إضافة النموذج بنجاح!**

🧠 **الملف**: ${file.path.split('/').last}
📊 **النوع**: TensorFlow Lite Model

💡 **لعرض النماذج**: اكتب "النماذج"
''';
        } else {
          response = '❌ فشل إضافة النموذج';
        }
      } else {
        response = '❌ نوع الملف غير مدعوم. الأنواع المدعومة: TXT, JSON, CSV, TFLite';
      }
    } catch (e) {
      response = '❌ خطأ في معالجة الملف: $e';
    }
    
    setState(() {
      _messages.add({'isUser': false, 'content': response, 'time': DateTime.now()});
      _isLoading = false;
    });
    _scrollToBottom();
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
            icon: const Icon(Icons.model_training),
            onPressed: () async {
              final models = await ModelService.getAvailableModels();
              String msg = '🧠 **النماذج المتاحة**\n\n';
              for (var m in models) {
                msg += '• ${m['name']} (${m['size']}) - ${m['status']}\n';
              }
              setState(() {
                _messages.add({'isUser': false, 'content': msg, 'time': DateTime.now()});
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('⚡ NUCLEAR MODE', style: TextStyle(fontSize: 10)),
                Text('🧠 ${ModelService.getActiveModel()['name']}', style: const TextStyle(fontSize: 10)),
                const Text('🚀 SPEED: MAX', style: TextStyle(fontSize: 10)),
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
                  onPressed: _uploadFile,
                  tooltip: 'رفع ملف',
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'اكتب أمراً أو ارفع ملف...',
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
