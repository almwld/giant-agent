import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../services/model_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  final ScrollController _scrollController = ScrollController();
  final ModelService _modelService = ModelService();
  
  bool _isLoading = false;
  bool _isSidebarOpen = false;
  bool _doNotDisturb = false;
  double _fontSize = 14.0;
  String _currentLanguage = 'ar';
  
  List<Map<String, dynamic>> _models = [];
  Map<String, dynamic> _activeModel = {};

  @override
  void initState() {
    super.initState();
    _init();
    _loadSettings();
  }
  
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _doNotDisturb = prefs.getBool('do_not_disturb') ?? false;
      _fontSize = prefs.getDouble('font_size') ?? 14.0;
      _currentLanguage = prefs.getString('language') ?? 'ar';
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
          'content': '[File: ${result.files.single.name}]\n${content.length > 500 ? content.substring(0, 500) + '...' : content}',
          'time': DateTime.now(),
        });
        _isLoading = true;
      });
      
      final response = await _modelService.generateResponse('Analyze this file: $content');
      
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
          'content': '[Image: ${image.name}]',
          'time': DateTime.now(),
        });
        _isLoading = true;
      });
      
      final response = await _modelService.generateResponse('Describe this image');
      
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
  }

  void _switchModel(String modelId) async {
    await _modelService.switchModel(modelId);
    setState(() {
      _activeModel = _modelService.getActiveModel();
      _isSidebarOpen = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Switched to: ${_activeModel['name']}')),
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

  void _showSettingsMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              title: const Text('Do Not Disturb'),
              value: _doNotDisturb,
              onChanged: (value) {
                setState(() => _doNotDisturb = value);
                SharedPreferences.getInstance().then((prefs) => prefs.setBool('do_not_disturb', value));
                Navigator.pop(context);
              },
            ),
            ListTile(
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
              title: const Text('Language'),
              trailing: DropdownButton<String>(
                value: _currentLanguage,
                items: const [
                  DropdownMenuItem(value: 'ar', child: Text('العربية')),
                  DropdownMenuItem(value: 'en', child: Text('English')),
                ],
                onChanged: (String? value) {
                  if (value != null) {
                    setState(() => _currentLanguage = value);
                    SharedPreferences.getInstance().then((prefs) => prefs.setString('language', value));
                    Navigator.pop(context);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
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
                      IconButton(
                        icon: const Icon(Icons.attach_file),
                        onPressed: _pickFile,
                        tooltip: 'Upload File',
                      ),
                      IconButton(
                        icon: const Icon(Icons.image),
                        onPressed: _pickImage,
                        tooltip: 'Upload Image',
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings),
                        onPressed: _showSettingsMenu,
                        tooltip: 'Settings',
                      ),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: _newConversation,
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
                  onPressed: _newConversation,
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
                  onPressed: () {
                    if (_messages.isNotEmpty) {
                      Share.share(_messages.last['content']);
                    }
                  },
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
                  onTap: () => _switchModel(model['id']),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

  // تحديث النماذج
  Future<void> _refreshModels() async {
    await _modelService.refreshModels();
    setState(() {
      _models = _modelService.getModels();
      _activeModel = _modelService.getActiveModel();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Models refreshed')),
    );
  }
