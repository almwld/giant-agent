import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/model_service.dart';

class FileBrowser extends StatefulWidget {
  const FileBrowser({super.key});

  @override
  State<FileBrowser> createState() => _FileBrowserState();
}

class _FileBrowserState extends State<FileBrowser> {
  final ModelService _modelService = ModelService();
  List<FileSystemEntity> _files = [];
  String _currentPath = '/storage/emulated/0/';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() => _isLoading = true);
    try {
      final dir = Directory(_currentPath);
      if (await dir.exists()) {
        final files = await dir.list().toList();
        setState(() {
          _files = files;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في الوصول: $e')),
      );
    }
  }

  Future<void> _pickModelFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['tflite', 'onnx', 'gguf', 'bin'],
    );
    
    if (result != null) {
      final filePath = result.files.single.path!;
      final fileName = result.files.single.name;
      
      // نسخ الملف إلى مجلد النماذج
      final modelsDir = Directory('/storage/emulated/0/Download/models/');
      if (!await modelsDir.exists()) {
        await modelsDir.create(recursive: true);
      }
      
      final destPath = '/storage/emulated/0/Download/models/$fileName';
      await File(filePath).copy(destPath);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ تم نسخ النموذج: $fileName')),
      );
      
      Navigator.pop(context, true);
    }
  }

  Future<void> _selectModel(String path) async {
    final fileName = path.split('/').last;
    if (fileName.endsWith('.tflite') || 
        fileName.endsWith('.onnx') || 
        fileName.endsWith('.gguf')) {
      
      // نسخ إلى مجلد النماذج
      final modelsDir = Directory('/storage/emulated/0/Download/models/');
      if (!await modelsDir.exists()) {
        await modelsDir.create(recursive: true);
      }
      
      final destPath = '/storage/emulated/0/Download/models/$fileName';
      await File(path).copy(destPath);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ تم اختيار النموذج: $fileName')),
      );
      
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚠️ هذا ليس ملف نموذج صالح')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('متصفح الملفات - $_currentPath'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _pickModelFile,
            tooltip: 'اختيار ملف',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // شريط التنقل السريع
                Container(
                  padding: const EdgeInsets.all(8),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      _buildQuickButton('المجلد الرئيسي', Icons.home, () {
                        setState(() {
                          _currentPath = '/storage/emulated/0/';
                          _loadFiles();
                        });
                      }),
                      _buildQuickButton('التحميلات', Icons.download, () {
                        setState(() {
                          _currentPath = '/storage/emulated/0/Download/';
                          _loadFiles();
                        });
                      }),
                      _buildQuickButton('النماذج', Icons.model_training, () {
                        setState(() {
                          _currentPath = '/storage/emulated/0/Download/models/';
                          _loadFiles();
                        });
                      }),
                      _buildQuickButton('SD Card', Icons.sd_storage, () {
                        setState(() {
                          _currentPath = '/sdcard/';
                          _loadFiles();
                        });
                      }),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _files.length,
                    itemBuilder: (context, index) {
                      final file = _files[index];
                      final isDirectory = FileSystemEntity.isDirectorySync(file.path);
                      final fileName = file.path.split('/').last;
                      final isModel = fileName.endsWith('.tflite') || 
                                      fileName.endsWith('.onnx') || 
                                      fileName.endsWith('.gguf');
                      
                      return ListTile(
                        leading: Icon(
                          isDirectory ? Icons.folder : (isModel ? Icons.model_training : Icons.insert_drive_file),
                          color: isDirectory ? Colors.blue : (isModel ? Colors.green : Colors.grey),
                        ),
                        title: Text(
                          fileName,
                          style: TextStyle(
                            fontWeight: isModel ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: isDirectory 
                            ? null 
                            : Text('${_formatSize(file.statSync().size)}'),
                        trailing: isModel
                            ? ElevatedButton(
                                onPressed: () => _selectModel(file.path),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                ),
                                child: const Text('تشغيل', style: TextStyle(fontSize: 12)),
                              )
                            : null,
                        onTap: () {
                          if (isDirectory) {
                            setState(() {
                              _currentPath = file.path;
                              _loadFiles();
                            });
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickModelFile,
        child: const Icon(Icons.add),
        tooltip: 'اختيار نموذج من الملفات',
      ),
    );
  }

  Widget _buildQuickButton(String label, IconData icon, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
