import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/model_service.dart';
import '../services/notification_service.dart';
import '../services/translation_service.dart';
import '../services/export_service.dart';
import '../services/backup_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  final ScrollController _scrollController = ScrollController();
  final ModelService _modelService = ModelService();
  final NotificationService _notificationService = NotificationService();
  final TranslationService _translationService = TranslationService();
  
  bool _isLoading = false;
  bool _isSidebarOpen = false;
  bool _doNotDisturb = false;
  double _fontSize = 14.0;
  String _currentLanguage = 'ar';
  
  List<Map<String, dynamic>> _models = [];
  Map<String, dynamic> _activeModel = {};
  
  // Tabs for multiple conversations
  final List<Map<String, dynamic>> _conversations = [];
  int _currentConversationIndex = 0;
  
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _init();
    _loadSettings();
    _initNotifications();
  }
  
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _doNotDisturb = prefs.getBool('do_not_disturb') ?? false;
      _fontSize = prefs.getDouble('font_size') ?? 14.0;
      _currentLanguage = prefs.getString('language') ?? 'ar';
    });
  }
  
  Future<void> _initNotifications() async {
    await _notificationService.init();
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
    
    // إشعار إذا كان هناك رد
    if (!_doNotDisturb && _messages.length % 5 == 0) {
      await _notificationService.showNotification('New Message', 'You have received a response');
    }
  }

  Future<void> _translateLastMessage() async {
    if (_messages.isEmpty) return;
    
    final lastMessage = _messages.last;
    final translated = await _translationService.translate(
      lastMessage['content'],
      to: _currentLanguage == 'ar' ? 'en' : 'ar',
    );
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Translation: $translated')),
    );
  }

  Future<void> _searchInConversation() async {
    final query = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Search'),
        content: TextField(
          decoration: const InputDecoration(hintText: 'Enter search term...'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
      ),
    );
    
    if (query != null && query.isNotEmpty) {
      final results = _messages.where((msg) => 
        msg['content'].toLowerCase().contains(query.toLowerCase())
      ).toList();
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Search Results (${results.length})'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              itemCount: results.length,
              itemBuilder: (context, index) {
                final msg = results[index];
                return ListTile(
                  title: Text(msg['content'].length > 100 ? msg['content'].substring(0, 100) + '...' : msg['content']),
                  subtitle: Text(msg['isUser'] ? 'User' : 'Agent'),
                  onTap: () => Navigator.pop(context),
                );
              },
            ),
          ),
        ),
      );
    }
  }

  void _showSettingsMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.notifications_off),
              title: const Text('Do Not Disturb'),
              trailing: Switch(
                value: _doNotDisturb,
                onChanged: (value) {
                  setState(() => _doNotDisturb = value);
                  SharedPreferences.getInstance().then((prefs) => prefs.setBool('do_not_disturb', value));
                  Navigator.pop(context);
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('Font Size'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: () {
                      setState(() => _fontSize = (_fontSize - 1).clamp(10.0, 24.0));
                      SharedPreferences.getInstance().then((prefs) => prefs.setDouble('font_size', _fontSize));
                    },
                  ),
                  Text('${_fontSize.toStringAsFixed(0)}'),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      setState(() => _fontSize = (_fontSize + 1).clamp(10.0, 24.0));
                      SharedPreferences.getInstance().then((prefs) => prefs.setDouble('font_size', _fontSize));
                    },
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.language),
              title: const Text('Language'),
              trailing: DropdownButton<String>(
                value: _currentLanguage,
                items: const [
                  DropdownMenuItem(value: 'ar', child: Text('العربية')),
                  DropdownMenuItem(value: 'en', child: Text('English')),
                ],
                onChanged: (value) {
                  setState(() => _currentLanguage = value!);
                  SharedPreferences.getInstance().then((prefs) => prefs.setString('language', value));
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
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
      body: Row(
        children: [
          // Sidebar
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: _isSidebarOpen ? 280 : 0,
            child: _isSidebarOpen ? _buildSidebar() : null,
          ),
          // Main Chat Area
          Expanded(
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(_isSidebarOpen ? Icons.menu_open : Icons.menu),
                        onPressed: () => setState(() => _isSidebarOpen = !_isSidebarOpen),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10A37F).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF10A37F),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _activeModel['name'] ?? 'No Model',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Advanced Action Buttons
                      IconButton(
                        icon: const Icon(Icons.translate),
                        onPressed: _translateLastMessage,
                        tooltip: 'Translate',
                      ),
                      IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: _searchInConversation,
                        tooltip: 'Search',
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings),
                        onPressed: _showSettingsMenu,
                        tooltip: 'Settings',
                      ),
                      IconButton(
                        icon: const Icon(Icons.share),
                        onPressed: () => ExportService.exportAsText(_messages),
                        tooltip: 'Export',
                      ),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () => setState(() => _messages.clear()),
                        tooltip: 'New Chat',
                      ),
                    ],
                  ),
                ),
                // Messages
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isUser = msg['isUser'] as bool;
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          decoration: BoxDecoration(
                            color: isUser ? const Color(0xFF10A37F) : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(
                                msg['content'],
                                style: TextStyle(
                                  color: isUser ? Colors.white : Colors.black87,
                                  fontSize: _fontSize,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${(msg['time'] as DateTime).hour}:${(msg['time'] as DateTime).minute.toString().padLeft(2, '0')}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isUser ? Colors.white70 : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // Loading
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: LinearProgressIndicator(),
                  ),
                // Input
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    border: Border(top: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          decoration: InputDecoration(
                            hintText: 'Message...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade100,
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
                            color: Color(0xFF10A37F),
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
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 280,
      color: Colors.grey.shade50,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                ElevatedButton.icon(
                  onPressed: () => setState(() => _messages.clear()),
                  icon: const Icon(Icons.add),
                  label: const Text('New Chat'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10A37F),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => ExportService.exportAsPdf(_messages, 'Chat Export'),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Export PDF'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => Share.share(_messages.last['content']),
                  icon: const Icon(Icons.share),
                  label: const Text('Share Last Message'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: const [
                Icon(Icons.model_training, size: 18, color: Colors.black54),
                SizedBox(width: 8),
                Text('Models', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _models.length,
              itemBuilder: (context, index) {
                final model = _models[index];
                final isActive = model['id'] == _activeModel['id'];
                return ListTile(
                  leading: Icon(
                    isActive ? Icons.check_circle : Icons.circle_outlined,
                    color: isActive ? const Color(0xFF10A37F) : Colors.grey,
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
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10A37F).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text('Active', style: TextStyle(fontSize: 10, color: Color(0xFF10A37F))),
                        )
                      : null,
                  onTap: () async {
                    await _modelService.switchModel(model['id']);
                    setState(() {
                      _activeModel = _modelService.getActiveModel();
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Switched to: ${model['name']}')),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

  // Voice Input
  Future<void> _startVoiceInput() async {
    final voiceService = VoiceService();
    await voiceService.init();
    
    await voiceService.startListening((text) {
      setState(() {
        _controller.text = text;
      });
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Listening... Speak now')),
    );
  }

  // Text-to-Speech
  Future<void> _speakLastMessage() async {
    if (_messages.isEmpty) return;
    final tts = TTSService();
    await tts.init();
    await tts.speak(_messages.last['content']);
  }

  // Analyze Image
  Future<void> _analyzeImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image != null) {
      setState(() {
        _messages.add({
          'isUser': true,
          'content': '[Analyzing Image: ${image.name}]',
          'time': DateTime.now(),
        });
        _isLoading = true;
      });
      
      final analysis = await ImageRecognitionService.analyzeImage(File(image.path));
      
      setState(() {
        _messages.add({
          'isUser': false,
          'content': analysis,
          'time': DateTime.now(),
        });
        _isLoading = false;
      });
    }
  }

  // Open Reminders
  void _openReminders() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RemindersScreen()),
    );
  }
