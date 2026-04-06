import 'dart:io';
import 'package:flutter/material.dart';
import '../services/agent_service.dart';
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
  final AgentService _agent = AgentService();
  bool _isLoading = false;
  String _thinkingMessage = 'جاري التفكير';
  int _processedFiles = 0;

  @override
  void initState() {
    super.initState();
    _initServices();
    _addWelcomeMessage();
    _loadStats();
  }

  Future<void> _initServices() async {
    await FileUploadService.initDB();
    await ModelService.getAvailableModels();
  }

  Future<void> _loadStats() async {
    final history = await FileUploadService.getHistory();
    setState(() {
      _processedFiles = history.length;
    });
  }

  void _addWelcomeMessage() {
    final activeModel = ModelService.getActiveModel();
    _messages.add({
      'isUser': false,
      'content': '''
☢️ **GIANT AGENT X** ☢️

**أقوى وكيل ذكاء اصطناعي في العالم!**

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🧠 **النموذج النشط**: ${activeModel['name']} v${activeModel['version']}

💥 **القدرات الخارقة:**

| الميزة | الوصف |
|--------|-------|
| 🧠 نماذج متعددة | دعم TFLite مع تبديل فوري |
| 📁 رفع ملفات | TXT, JSON, CSV, TFLite |
| 🌐 إنشاء مواقع | HTML كامل مع تصميم عصري |
| 💻 أكواد برمجية | Dart, Python, JavaScript |
| 📊 تحليل نصوص | إحصائيات وتحليل مشاعر |
| 🔢 عمليات حسابية | جمع، طرح، ضرب، قسمة |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

⚡ **الأوامر السريعة:**

• `النماذج` - عرض النماذج المتاحة
• `تبديل نموذج [الاسم]` - تبديل النموذج
• `رفع ملف` - تعليمات رفع الملفات
• `تاريخ الملفات` - عرض الملفات المرفوعة
• `أنشئ موقعاً` - إنشاء HTML
• `اكتب كود` - إنشاء كود
• `قاعدة بيانات` - إحصائيات القاعدة

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔥 **ابدأ الآن!** اكتب أمراً أو استخدم الأزرار السريعة أدناه.
''',
      'intent': 'welcome',
      'time': DateTime.now(),
    });
  }

  Future<void> _uploadFile() async {
    final file = await FileUploadService.pickFile();
    if (file == null) return;

    setState(() {
      _isLoading = true;
      _thinkingMessage = 'جاري معالجة الملف';
      _messages.add({
        'isUser': true,
        'content': '📁 **رفع ملف**: ${file.path.split('/').last}',
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
✅ **تمت معالجة الملف النصي بنجاح!**

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📁 **الملف**: ${analysis['filename']}
📊 **الأسطر**: ${analysis['lines']}
📝 **الكلمات**: ${analysis['words']}
📏 **الحجم**: ${(analysis['size'] / 1024).toStringAsFixed(2)} KB

💾 **تم حفظ الملف في قاعدة البيانات العملاقة**

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''';
      } else if (ext == 'json') {
        final analysis = await FileUploadService.processJsonFile(file);
        response = '''
✅ **تمت معالجة ملف JSON بنجاح!**

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📁 **الملف**: ${analysis['filename']}
🔑 **عدد المفاتيح**: ${analysis['keys']}
📏 **الحجم**: ${(analysis['size'] / 1024).toStringAsFixed(2)} KB

💾 **تم حفظ البيانات في قاعدة البيانات**

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''';
      } else if (ext == 'csv') {
        final analysis = await FileUploadService.processCsvFile(file);
        response = '''
✅ **تمت معالجة ملف CSV بنجاح!**

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📁 **الملف**: ${analysis['filename']}
📊 **الصفوف**: ${analysis['rows']}
📐 **الأعمدة**: ${analysis['columns']}
📏 **الحجم**: ${(analysis['size'] / 1024).toStringAsFixed(2)} KB

💾 **تم حفظ الجدول في قاعدة البيانات**

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''';
      } else if (ext == 'tflite') {
        final added = await ModelService.addCustomModel(file.path);
        if (added) {
          response = '''
✅ **تم إضافة النموذج بنجاح!**

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🧠 **الملف**: ${file.path.split('/').last}
📊 **النوع**: TensorFlow Lite Model
💾 **الحجم**: ${(await file.length() / 1024 / 1024).toStringAsFixed(2)} MB

💡 **لعرض النماذج**: اكتب "النماذج"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''';
        } else {
          response = '❌ فشل إضافة النموذج';
        }
      } else {
        response = '''
❌ **نوع الملف غير مدعوم**

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📂 **الأنواع المدعومة**:
• TXT - ملفات نصية
• JSON - بيانات منظمة
• CSV - جداول بيانات
• TFLite - نماذج ذكاء اصطناعي

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''';
      }
      await _loadStats();
    } catch (e) {
      response = '❌ **خطأ في معالجة الملف**: $e';
    }

    setState(() {
      _messages.add({
        'isUser': false,
        'content': response,
        'intent': 'file_upload',
        'confidence': 0.95,
        'time': DateTime.now(),
      });
      _isLoading = false;
    });
    _scrollToBottom();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({
        'isUser': true,
        'content': text,
        'time': DateTime.now(),
      });
      _controller.clear();
      _isLoading = true;
      _thinkingMessage = '🧠 جاري التفكير العميق';
    });
    _scrollToBottom();

    final response = await _agent.process(text);

    setState(() {
      _messages.add({
        'isUser': false,
        'content': response,
        'intent': 'response',
        'confidence': 0.92,
        'time': DateTime.now(),
      });
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

  void _showModels() async {
    final models = await ModelService.getAvailableModels();
    String content = '🧠 **النماذج المتاحة**\n\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n';
    for (var model in models) {
      content += '''
📦 **${model['name']}**
   • الإصدار: ${model['version']}
   • الحجم: ${model['size']}
   • النوع: ${model['type']}
   • الحالة: ${model['status'] == 'active' ? '✅ نشط' : '📦 متاح'}

''';
    }
    content += '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n';
    content += '💡 **لتبديل النموذج**: اكتب "تبديل نموذج [الاسم]"';

    setState(() {
      _messages.add({
        'isUser': false,
        'content': content,
        'intent': 'models',
        'confidence': 0.99,
        'time': DateTime.now(),
      });
    });
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final activeModel = ModelService.getActiveModel();
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(100),
        child: Column(
          children: [
            AppBar(
              title: const Text('💀 GIANT AGENT X'),
              centerTitle: true,
              backgroundColor: Colors.deepPurple,
              elevation: 0,
              actions: [
                IconButton(
                  icon: const Icon(Icons.model_training),
                  onPressed: _showModels,
                  tooltip: 'النماذج المتاحة',
                ),
              ],
            ),
            ModelSelector(
              onModelChanged: () {
                setState(() {});
                _addWelcomeMessage();
              },
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          StatusBar(
            modelName: activeModel['name'],
            processedFiles: _processedFiles,
            speed: 'MAX',
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return ChatBubble(
                  isUser: msg['isUser'],
                  message: msg['content'],
                  time: msg['time'],
                  intent: msg['intent'],
                  confidence: msg['confidence'],
                );
              },
            ),
          ),
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.all(8),
              child: ThinkingIndicator(message: _thinkingMessage),
            ),
          QuickActions(onTap: (cmd) {
            _controller.text = cmd;
            _sendMessage();
          }),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              border: Border(top: BorderSide(color: Colors.deepPurple.shade700)),
            ),
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.deepPurple.shade600, Colors.deepPurple.shade800],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.attach_file, color: Colors.white),
                    onPressed: _uploadFile,
                    tooltip: 'رفع ملف',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'اكتب أمراً أو ارفع ملف...',
                        hintStyle: TextStyle(color: Colors.grey.shade500),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.deepPurple, Colors.deepPurple.shade700],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: _sendMessage,
                    tooltip: 'إرسال',
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

  void _showBenchmark() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const BenchmarkScreen()),
    );
  }
