import '../screens/advanced_settings.dart';
import '../services/image_analyzer.dart';
import '../services/share_service.dart';
import '../services/voice_service.dart';
import ../services/database_service.dart;
import ../screens/settings_screen.dart;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../services/model_service.dart';
import 'file_browser.dart';

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
  List<Map<String, dynamic>> _models = [];
  Map<String, dynamic> _activeModel = {};

  @override
  void initState() {
    super.initState();
    _init();
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تحديث النماذج')),
    );
  }

  Future<void> _addModel() async {
    bool added = await _modelService.addModelFromFile();
    if (added) {
      await _refreshModels();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ تم إضافة النموذج بنجاح')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ فشل إضافة النموذج')),
      );
    }
  }

  Future<void> _openFileBrowser() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const FileBrowser()),
    );
    if (result == true) {
      await _refreshModels();
    }
  }

  Future<void> _sendMessage() async {
    await DatabaseService.saveMessage(text, true);
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    
    if (!_modelService.hasActiveModel()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ يرجى تحميل نموذج أولاً من القائمة الجانبية')),
      );
      return;
    }

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

    final response = await _modelService.runModel(text);

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

  void _newConversation() {
    setState(() {
      _messages.clear();
    });
  }

  void _switchModel(Map<String, dynamic> model) async {
    if (model['id'] == 'no_model') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ لا يوجد نموذج محدد')),
      );
      return;
    }
    
    await _modelService.switchModel(model['id']);
    setState(() {
      _activeModel = _modelService.getActiveModel();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم التبديل إلى: ${model['name']}')),
    );
    Navigator.pop(context);
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
        title: const Text('Giant Agent X'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshModels,
            tooltip: 'تحديث النماذج',
          ),
          IconButton(
            icon: const Icon(Icons.add_box),
            onPressed: _addModel,
            tooltip: 'إضافة نموذج',
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _openFileBrowser,
            tooltip: 'متصفح الملفات',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _newConversation,
            tooltip: 'محادثة جديدة',
          ),
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            Container(
              height: 150,
              decoration: BoxDecoration(
                color: Colors.deepPurple,
              ),
              child: const Center(
                child: Text(
                  'Giant Agent X',
                  style: TextStyle(fontSize: 24, color: Colors.white),
                ),
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
                      color: isActive ? Colors.green : Colors.grey,
                    ),
                    title: Text(model['name']),
                    subtitle: Text('${model['size']} MB • ${model['type']}'),
                    trailing: isActive
                        ? const Text('نشط', style: TextStyle(color: Colors.green))
                        : null,
                    onTap: () => _switchModel(model),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: _modelService.hasActiveModel() ? Colors.green.shade50 : Colors.red.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _modelService.hasActiveModel() ? Icons.check_circle : Icons.warning,
                  size: 16,
                  color: _modelService.hasActiveModel() ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _modelService.hasActiveModel() 
                        ? 'النموذج النشط: ${_modelService.getActiveModelName()}' 
                        : '⚠️ الرجاء تحميل نموذج TFLite من القائمة الجانبية',
                    style: TextStyle(
                      color: _modelService.hasActiveModel() ? Colors.green : Colors.orange,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
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
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.8,
                    ),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.deepPurple : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          msg['content'],
                          style: TextStyle(
                            color: isUser ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${(msg['time'] as DateTime).hour}:${(msg['time'] as DateTime).minute}',
                          style: TextStyle(
                            fontSize: 10,
                            color: isUser ? Colors.white70 : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: _modelService.hasActiveModel(),
                    decoration: InputDecoration(
                      hintText: _modelService.hasActiveModel() 
                          ? 'اكتب رسالتك...' 
                          : 'قم بتحميل نموذج TFLite أولاً',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                    ),
                    onSubmitted: (_) => _sendMessage(),
    await DatabaseService.saveMessage(text, true);
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sendMessage,
    await DatabaseService.saveMessage(text, true);
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
