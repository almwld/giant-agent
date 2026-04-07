import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../services/model_service.dart';
import '../core/theme.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/input_bar.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  final ScrollController _scrollController = ScrollController();
  final ModelService _modelService = ModelService();
  
  bool _isLoading = false;
  bool _isDarkMode = false;
  List<Map<String, dynamic>> _models = [];
  Map<String, dynamic> _activeModel = {};

  @override
  void initState() {
    super.initState();
    _init();
    _loadTheme();
  }
  
  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = prefs.getBool('dark_mode') ?? false;
    });
  }

  Future<void> _init() async {
    await _modelService.init();
    setState(() {
      _models = _modelService.getModels();
      _activeModel = _modelService.getActiveModel();
    });
  }

  Future<void> _refreshModels() async {
    await _modelService.refreshModels();
    setState(() {
      _models = _modelService.getModels();
      _activeModel = _modelService.getActiveModel();
    });
    _showSnackbar('تم تحديث النماذج');
  }

  Future<void> _addModel() async {
    bool added = await _modelService.addModelFromFile();
    if (added) {
      await _refreshModels();
      _showSnackbar('✅ تم إضافة النموذج بنجاح');
    } else {
      _showSnackbar('❌ فشل إضافة النموذج');
    }
  }

  void _showSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _sendMessage() async {
    String text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({
        'isUser': true,
        'content': text,
        'time': DateTime.now(),
      });
      _controller.clear();
      _isLoading = true;
    });
    _scrollToBottom();

    String response = await _modelService.generateResponse(text);

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

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) {
      File file = File(result.files.single.path!);
      String content = await file.readAsString();
      
      setState(() {
        _messages.add({
          'isUser': true,
          'content': '📁 **${result.files.single.name}**\n${content.length > 500 ? content.substring(0, 500) + '...' : content}',
          'time': DateTime.now(),
        });
        _isLoading = true;
      });
      
      String response = await _modelService.generateResponse('حلل هذا الملف: $content');
      
      setState(() {
        _messages.add({
          'isUser': false,
          'content': response,
          'time': DateTime.now(),
        });
        _isLoading = false;
      });
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _messages.add({
          'isUser': true,
          'content': '🖼️ **${image.name}**',
          'time': DateTime.now(),
        });
        _isLoading = true;
      });
      
      String response = await _modelService.generateResponse('وصف هذه الصورة');
      
      setState(() {
        _messages.add({
          'isUser': false,
          'content': response,
          'time': DateTime.now(),
        });
        _isLoading = false;
      });
    }
  }

  void _newConversation() {
    setState(() {
      _messages.clear();
    });
    _showSnackbar('تم بدء محادثة جديدة');
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

  void _toggleTheme() async {
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', _isDarkMode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _isDarkMode ? AppTheme.darkTheme : AppTheme.lightTheme,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Giant Agent X'),
          centerTitle: true,
          actions: [
            IconButton(
              icon: Icon(_isDarkMode ? Icons.light_mode : Icons.dark_mode),
              onPressed: _toggleTheme,
              tooltip: 'تبديل المظهر',
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshModels,
              tooltip: 'تحديث النماذج',
            ),
          ],
        ),
        drawer: _buildDrawer(),
        body: Column(
          children: [
            // شريط النموذج النشط
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                border: Border(
                  bottom: BorderSide(color: AppTheme.primary.withOpacity(0.2)),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppTheme.secondary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'النموذج النشط: ${_activeModel['name'] ?? "Built-in"}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const Spacer(),
                  Text(
                    '${_models.length} نموذج',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            // الرسائل
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 64,
                            color: AppTheme.textLight.withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'لا توجد رسائل بعد',
                            style: TextStyle(color: AppTheme.textLight),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'ابدأ المحادثة بإرسال رسالة',
                            style: TextStyle(fontSize: 12, color: AppTheme.textLight),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        Map<String, dynamic> msg = _messages[index];
                        return ChatBubble(
                          message: msg['content'],
                          isUser: msg['isUser'],
                          time: msg['time'],
                          modelName: msg['isUser'] ? null : _activeModel['name'],
                        );
                      },
                    ),
            ),
            // شريط الإدخال
            InputBar(
              controller: _controller,
              onSend: _sendMessage,
              onAttach: _pickFile,
              onImage: _pickImage,
              isLoading: _isLoading,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Column(
        children: [
          // Header
          Container(
            height: 180,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
            ),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.bolt,
                    size: 48,
                    color: Colors.white,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Giant Agent X',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'الوكيل العملاق',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
          // الإجراءات السريعة
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildDrawerItem(
                  icon: Icons.add,
                  title: 'محادثة جديدة',
                  color: AppTheme.primary,
                  onTap: _newConversation,
                ),
                const SizedBox(height: 8),
                _buildDrawerItem(
                  icon: Icons.add_box,
                  title: 'إضافة نموذج',
                  color: AppTheme.secondary,
                  onTap: _addModel,
                ),
                const SizedBox(height: 8),
                _buildDrawerItem(
                  icon: Icons.refresh,
                  title: 'تحديث النماذج',
                  color: AppTheme.accent,
                  onTap: _refreshModels,
                ),
              ],
            ),
          ),
          const Divider(),
          // قائمة النماذج
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.model_training, size: 18, color: AppTheme.textLight),
                const SizedBox(width: 8),
                Text(
                  'النماذج المتاحة',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textLight,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _models.length,
              itemBuilder: (context, index) {
                Map<String, dynamic> model = _models[index];
                bool isActive = model['id'] == _activeModel['id'];
                return ListTile(
                  leading: Icon(
                    isActive ? Icons.check_circle : Icons.circle_outlined,
                    color: isActive ? AppTheme.secondary : AppTheme.textLight,
                    size: 20,
                  ),
                  title: Text(
                    model['name'],
                    style: TextStyle(
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text('${model['size']} MB • ${model['type']}'),
                  trailing: isActive
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.secondary.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'نشط',
                            style: TextStyle(fontSize: 10, color: AppTheme.secondary),
                          ),
                        )
                      : null,
                  onTap: () async {
                    await _modelService.switchModel(model['id']);
                    setState(() {
                      _activeModel = _modelService.getActiveModel();
                    });
                    Navigator.pop(context);
                    _showSnackbar('تم التبديل إلى ${model['name']}');
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(title),
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.1),
          foregroundColor: color,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

// إضافة أوامر Python
Widget _buildPythonCommands() {
  return Container(
    padding: const EdgeInsets.all(8),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildCommandChip('📊 تحليل بيانات', 'تحليل بيانات 10,20,30,40,50'),
        _buildCommandChip('🌐 تطبيق Flask', 'إنشاء تطبيق فلاسك myapp'),
        _buildCommandChip('📝 تحليل نص', 'تحليل نص الذكاء الاصطناعي'),
        _buildCommandChip('🧠 تعلم آلة', 'تعلم آلة'),
        _buildCommandChip('🚀 FastAPI', 'إنشاء api myapi'),
        _buildCommandChip('⚡ أتمتة', 'أتمتة المهام'),
      ],
    ),
  );
}

Widget _buildCommandChip(String label, String command) {
  return ActionChip(
    label: Text(label, style: const TextStyle(fontSize: 12)),
    onPressed: () {
      _controller.text = command;
      _sendMessage();
    },
    backgroundColor: AppTheme.primary.withOpacity(0.1),
    labelStyle: TextStyle(color: AppTheme.primary),
  );
}

  // إضافة الأوامر السريعة
  void _showQuickCommands() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        height: 400,
        child: Column(
          children: [
            const Text(
              'الأوامر السريعة',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: CommandGrid(onCommandSelected: (command) {
                Navigator.pop(context);
                _controller.text = command;
                _sendMessage();
              }),
            ),
          ],
        ),
      ),
    );
  }

  // تصدير المحادثة
  Future<void> _exportConversation() async {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'تصدير المحادثة',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.description),
              title: const Text('Markdown'),
              onTap: () async {
                Navigator.pop(context);
                await ExportService.exportConversationAsMarkdown(_messages);
                _showSnackbar('تم التصدير بنجاح');
              },
            ),
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('JSON'),
              onTap: () async {
                Navigator.pop(context);
                await ExportService.exportAsJson(_messages);
                _showSnackbar('تم التصدير بنجاح');
              },
            ),
          ],
        ),
      ),
    );
  }

  // إضافة زر الأوامر السريعة والتصدير
  // أضف في AppBar:
  // IconButton(
  //   icon: const Icon(Icons.grid_view),
  //   onPressed: _showQuickCommands,
  // ),
  // IconButton(
  //   icon: const Icon(Icons.download),
  //   onPressed: _exportConversation,
  // ),
