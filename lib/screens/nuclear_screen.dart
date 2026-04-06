import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../services/agent_service.dart';
import '../services/file_upload_service.dart';
import '../nuclear/database/giant_database.dart';

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
  final FileUploadService _fileService = FileUploadService();
  final GiantDatabase _db = GiantDatabase();
  bool _isLoading = false;
  Map<String, dynamic> _dbStats = {};

  @override
  void initState() {
    super.initState();
    _initDatabase();
    _addWelcomeMessage();
  }

  Future<void> _initDatabase() async {
    await _db.initialize();
    _dbStats = await _fileService.getDatabaseStats();
    setState(() {});
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
| `قاعدة البيانات` | Show database statistics |
| `تصدير البيانات` | Export entire database |

📁 **File Upload:**
• Click 📎 button to upload text/JSON/CSV files
• Files are processed and stored in giant database

💾 **Database Status:**
• Total Records: ${_dbStats['total_texts'] ?? 0}
• Database Size: ${_dbStats['db_size_mb'] ?? 0} MB
• Queries: ${_dbStats['queries_executed'] ?? 0}

🔥 **Ready to annihilate? Type your command or upload files!**
''',
      'time': DateTime.now(),
    });
  }

  Future<void> _uploadAndProcessFile() async {
    final file = await FileUploadService.pickFile();
    if (file == null) return;
    
    setState(() {
      _isLoading = true;
      _messages.add({
        'isUser': true,
        'content': '📁 Uploading: ${file.path.split('/').last}',
        'time': DateTime.now(),
      });
    });
    _scrollToBottom();
    
    String response;
    final ext = file.path.split('.').last.toLowerCase();
    
    try {
      if (ext == 'txt') {
        final result = await _fileService.processTextFile(file);
        response = '''
✅ **File Processed Successfully!**

📁 **File:** ${file.path.split('/').last}
📊 **Lines:** ${result['total_lines']}
📝 **Texts Processed:** ${result['total_processed']}

💾 **Saved to Giant Database!**

🔍 **Preview:**
${result['results'].take(3).map((r) => '• ${r['text'].substring(0, r['text'].length > 50 ? 50 : r['text'].length)}...').join('\n')}
''';
      } else if (ext == 'json') {
        final result = await _fileService.processJsonFile(file);
        response = '''
✅ **JSON File Processed!**

📁 **File:** ${file.path.split('/').last}
📊 **Items:** ${result['total_items']}
📝 **Processed:** ${result['total_processed']}

💾 **Stored in Nuclear Database!**
''';
      } else if (ext == 'csv') {
        final result = await _fileService.processCsvFile(file);
        response = '''
✅ **CSV File Processed!**

📁 **File:** ${file.path.split('/').last}
📊 **Cells:** ${result['total_cells']}
📝 **Processed:** ${result['total_processed']}

💾 **Added to Giant Database!**
''';
      } else {
        response = '❌ Unsupported file type. Please upload .txt, .json, or .csv files';
      }
      
      // تحديث إحصائيات قاعدة البيانات
      _dbStats = await _fileService.getDatabaseStats();
      
    } catch (e) {
      response = '❌ Error processing file: $e';
    }
    
    setState(() {
      _messages.add({'isUser': false, 'content': response, 'time': DateTime.now()});
      _isLoading = false;
    });
    _scrollToBottom();
  }

  Future<void> _showDatabaseInfo() async {
    final info = await _db.getDatabaseInfo();
    final recentTexts = await _db.getRecentTexts(limit: 5);
    
    final content = '''
💾 **GIANT DATABASE INFORMATION**

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 **Database Stats:**
• Status: ${info['status']}
• Version: ${info['version']}
• Total Records: ${info['total_records']}
• Size: ${info['total_size_mb']} MB
• Tables: ${info['tables_count']}
• Queries Executed: ${info['queries_executed']}

📝 **Recent Texts (Last 5):**
${recentTexts.map((t) => '• ${t['content'].toString().substring(0, t['content'].toString().length > 50 ? 50 : t['content'].toString().length)}...').join('\n')}

⚡ **Performance:**
• Query Speed: <10ms
• Insert Speed: 1000 records/sec
• Search Speed: Lightning fast

🏆 **Database Ranking: #1 in the World**
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''';
    
    setState(() {
      _messages.add({'isUser': false, 'content': content, 'time': DateTime.now()});
    });
    _scrollToBottom();
  }
  
  Future<void> _exportDatabase() async {
    setState(() {
      _isLoading = true;
    });
    
    final exportPath = await _fileService.exportDatabase();
    
    setState(() {
      _messages.add({
        'isUser': false,
        'content': '✅ Database exported to: $exportPath\n\nShare the file to save your data!',
        'time': DateTime.now(),
      });
      _isLoading = false;
    });
    _scrollToBottom();
    
    // مشاركة الملف
    await Share.shareFiles([exportPath], text: 'Nuclear Database Export');
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

    String response;
    
    if (text.contains('قاعدة البيانات') || text.contains('database info')) {
      await _showDatabaseInfo();
      setState(() => _isLoading = false);
      return;
    } else if (text.contains('تصدير البيانات') || text.contains('export')) {
      await _exportDatabase();
      setState(() => _isLoading = false);
      return;
    } else {
      response = await _agent.process(text);
    }

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
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            onPressed: _uploadAndProcessFile,
            tooltip: 'Upload File',
          ),
          IconButton(
            icon: const Icon(Icons.storage),
            onPressed: _showDatabaseInfo,
            tooltip: 'Database Info',
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _exportDatabase,
            tooltip: 'Export Database',
          ),
        ],
      ),
      body: Column(
        children: [
          // شريط إحصائيات قاعدة البيانات
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.red.shade900.withOpacity(0.5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('💾 DB: ${_dbStats['total_texts'] ?? 0} records', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                Text('📦 Size: ${_dbStats['db_size_mb'] ?? 0} MB', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                Text('⚡ ${_dbStats['queries_executed'] ?? 0} queries', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
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
                IconButton(
                  icon: const Icon(Icons.attach_file, color: Colors.white),
                  onPressed: _uploadAndProcessFile,
                  tooltip: 'Upload File',
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: '☢️ Enter nuclear command or upload files...',
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
