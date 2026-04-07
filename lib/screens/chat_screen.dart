import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../services/model_service.dart';
import '../core/theme.dart';
import '../widgets/future_message_bubble.dart';

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
  double _fontSize = 14.0;
  int _selectedNavIndex = 0;
  
  List<Map<String, dynamic>> _models = [];
  Map<String, dynamic> _activeModel = {};
  
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _init();
    _loadSettings();
    
    _glowController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
  }
  
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = prefs.getBool('dark_mode') ?? false;
      _fontSize = prefs.getDouble('font_size') ?? 14.0;
    });
  }

  Future<void> _init() async {
    await _modelService.init();
    setState(() {
      _models = _modelService.getModels();
      _activeModel = _modelService.getActiveModel();
    });
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
    });
    _scrollToBottom();

    final response = await _modelService.generateResponse(text);

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
      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      
      setState(() {
        _messages.add({
          'isUser': true,
          'content': '📁 ${result.files.single.name}\n${content.length > 500 ? content.substring(0, 500) + '...' : content}',
          'time': DateTime.now(),
        });
        _isLoading = true;
      });
      
      final response = await _modelService.generateResponse('حلل هذا الملف: $content');
      
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
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image != null) {
      setState(() {
        _messages.add({
          'isUser': true,
          'content': '🖼️ ${image.name}',
          'time': DateTime.now(),
        });
        _isLoading = true;
      });
      
      final response = await _modelService.generateResponse('وصف هذه الصورة');
      
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

  void _toggleTheme() {
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('dark_mode', _isDarkMode);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
        title: AnimatedBuilder(
          animation: _glowController,
          builder: (context, child) {
            return ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [AppTheme.primaryColor, AppTheme.secondaryColor],
              ).createShader(bounds),
              child: const Text(
                'Giant Agent X',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            );
          },
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(_isDarkMode ? Icons.light_mode : Icons.dark_mode),
            onPressed: _toggleTheme,
          ),
        ],
      ),
      drawer: _buildNeonDrawer(),
      body: Container(
        decoration: BoxDecoration(
          gradient: _isDarkMode ? AppTheme.darkGradient : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Color(0xFFF5F5F5)],
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 80),
            // Active Model Indicator
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withOpacity(0.3),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bolt, size: 16, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    _activeModel['name'] ?? 'AI Model Active',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Messages
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(20),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  return FutureMessageBubble(
                    message: msg['content'],
                    isUser: msg['isUser'],
                    time: msg['time'],
                    fontSize: _fontSize,
                  );
                },
              ),
            ),
            // Loading
            if (_isLoading)
              Padding(
                padding: const EdgeInsets.all(8),
                child: LinearProgressIndicator(
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                ),
              ),
            // Input Area
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _isDarkMode ? AppTheme.darkGlassColor : AppTheme.glassWhite,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: AppTheme.primaryColor.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    onPressed: _pickFile,
                    color: AppTheme.primaryColor,
                  ),
                  IconButton(
                    icon: const Icon(Icons.image),
                    onPressed: _pickImage,
                    color: AppTheme.secondaryColor,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: TextStyle(fontSize: _fontSize),
                      decoration: const InputDecoration(
                        hintText: 'اكتب رسالتك...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _glowController,
                    builder: (context, child) {
                      return Container(
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryColor.withOpacity(0.5),
                              blurRadius: 10 * _glowController.value,
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.send, color: Colors.white),
                          onPressed: _sendMessage,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNeonDrawer() {
    return Drawer(
      backgroundColor: _isDarkMode ? const Color(0xFF1A1A2E) : Colors.white,
      child: Container(
        decoration: BoxDecoration(
          gradient: _isDarkMode ? AppTheme.darkGradient : null,
        ),
        child: Column(
          children: [
            Container(
              height: 200,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'GX',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Giant Agent X',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _buildDrawerItem(Icons.chat_bubble_outline, 'الدردشة', () {
              Navigator.pop(context);
              setState(() => _selectedNavIndex = 0);
            }),
            _buildDrawerItem(Icons.model_training_outlined, 'النماذج', () {
              Navigator.pop(context);
              setState(() => _selectedNavIndex = 1);
            }),
            _buildDrawerItem(Icons.folder_outlined, 'الملفات', _pickFile),
            _buildDrawerItem(Icons.person_outline, 'الملف الشخصي', () {}),
            _buildDrawerItem(Icons.settings_outlined, 'الإعدادات', () {}),
            const Spacer(),
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: AppTheme.secondaryGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Text(
                    'AI Model Active',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _activeModel['name'] ?? 'Built-in',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.primaryColor),
      title: Text(title),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}

  // إضافة نموذج
  Future<void> _addModel() async {
    final added = await _modelService.addModelFromFile();
    if (added) {
      await _refreshModels();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ تم إضافة النموذج بنجاح')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ لم يتم إضافة النموذج. تأكد من اختيار ملف .tflite')),
      );
    }
  }
