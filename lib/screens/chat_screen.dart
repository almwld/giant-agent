import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
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
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _sendMessage() async {
    String text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({'isUser': true, 'content': text, 'time': DateTime.now()});
      _controller.clear();
      _isLoading = true;
    });
    _scrollToBottom();

    String response = await _modelService.generateResponse(text);

    setState(() {
      _messages.add({'isUser': false, 'content': response, 'time': DateTime.now()});
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
          'content': '📁 ${result.files.single.name}\n${content.length > 500 ? content.substring(0, 500) + '...' : content}',
          'time': DateTime.now(),
        });
        _isLoading = true;
      });
      
      String response = await _modelService.generateResponse('حلل هذا الملف: $content');
      
      setState(() {
        _messages.add({'isUser': false, 'content': response, 'time': DateTime.now()});
        _isLoading = false;
      });
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _messages.add({'isUser': true, 'content': '🖼️ ${image.name}', 'time': DateTime.now()});
        _isLoading = true;
      });
      
      String response = await _modelService.generateResponse('وصف هذه الصورة');
      
      setState(() {
        _messages.add({'isUser': false, 'content': response, 'time': DateTime.now()});
        _isLoading = false;
      });
    }
  }

  void _newConversation() {
    setState(() {
      _messages.clear();
    });
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
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            Container(
              height: 150,
              color: Colors.deepPurple,
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
                  Map<String, dynamic> model = _models[index];
                  bool isActive = model['id'] == _activeModel['id'];
                  return ListTile(
                    leading: Icon(isActive ? Icons.check_circle : Icons.circle_outlined,
                        color: isActive ? Colors.green : Colors.grey),
                    title: Text(model['name']),
                    subtitle: Text('${model['size']} MB • ${model['type']}'),
                    trailing: isActive ? const Text('نشط', style: TextStyle(color: Colors.green)) : null,
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
      ),
      body: Column(
        children: [
          // شريط النموذج النشط
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.deepPurple.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.model_training, size: 16),
                const SizedBox(width: 8),
                Text('النموذج النشط: ${_activeModel['name'] ?? "Built-in"}'),
              ],
            ),
          ),
          // الرسائل
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                Map<String, dynamic> msg = _messages[index];
                bool isUser = msg['isUser'];
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
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
                          style: TextStyle(color: isUser ? Colors.white : Colors.black87),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${(msg['time'] as DateTime).hour}:${(msg['time'] as DateTime).minute}',
                          style: TextStyle(fontSize: 10, color: isUser ? Colors.white70 : Colors.grey),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(),
          // منطقة الإدخال
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  onPressed: _pickFile,
                  tooltip: 'رفع ملف',
                ),
                IconButton(
                  icon: const Icon(Icons.image),
                  onPressed: _pickImage,
                  tooltip: 'رفع صورة',
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'اكتب رسالتك...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade100,
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
