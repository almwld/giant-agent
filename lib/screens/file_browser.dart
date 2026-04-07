import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class FileBrowser extends StatefulWidget {
  const FileBrowser({super.key});

  @override
  State<FileBrowser> createState() => _FileBrowserState();
}

class _FileBrowserState extends State<FileBrowser> {
  List<FileSystemEntity> _files = [];
  String _currentPath = '/storage/emulated/0/';
  bool _isLoading = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _requestPermission();
  }

  Future<void> _requestPermission() async {
    final status = await Permission.storage.request();
    if (status.isGranted) {
      _loadFiles();
    } else {
      setState(() => _error = 'صلاحية التخزين مطلوبة');
    }
  }

  Future<void> _loadFiles() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });
    
    try {
      final dir = Directory(_currentPath);
      if (await dir.exists()) {
        final files = await dir.list().toList();
        setState(() {
          _files = files;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'المجلد غير موجود';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'خطأ: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _pickModelDirectly() async {
    // استخدام FilePicker لاختيار أي ملف من الهاتف
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['tflite', 'onnx', 'gguf', 'bin'],
      dialogTitle: 'اختر ملف النموذج',
    );
    
    if (result != null) {
      final filePath = result.files.single.path!;
      final fileName = result.files.single.name;
      
      // إنشاء مجلد النماذج إذا لم يكن موجوداً
      final modelsDir = Directory('/storage/emulated/0/Download/models/');
      if (!await modelsDir.exists()) {
        await modelsDir.create(recursive: true);
      }
      
      // نسخ الملف إلى مجلد النماذج
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
    final fileExt = fileName.split('.').last.toLowerCase();
    
    if (fileExt == 'tflite' || fileExt == 'onnx' || fileExt == 'gguf' || fileExt == 'bin') {
      // إنشاء مجلد النماذج إذا لم يكن موجوداً
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
        SnackBar(content: Text('⚠️ هذا ليس ملف نموذج صالح (يجب أن يكون .tflite أو .onnx أو .gguf)')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('متصفح الملفات - ${_currentPath.split('/').last}'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _pickModelDirectly,
            tooltip: 'اختيار ملف',
          ),
        ],
      ),
      body: Column(
        children: [
          // أزرار سريعة
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
                _buildQuickButton('اختيار ملف', Icons.file_upload, _pickModelDirectly),
              ],
            ),
          ),
          // رسالة الخطأ
          if (_error.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.red.shade50,
              child: Text(_error, style: const TextStyle(color: Colors.red)),
            ),
          // قائمة الملفات
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _files.isEmpty
                    ? const Center(child: Text('لا توجد ملفات في هذا المجلد'))
                    : ListView.builder(
                        itemCount: _files.length,
                        itemBuilder: (context, index) {
                          final file = _files[index];
                          final isDirectory = FileSystemEntity.isDirectorySync(file.path);
                          final fileName = file.path.split('/').last;
                          final fileExt = fileName.split('.').last.toLowerCase();
                          final isModel = fileExt == 'tflite' || fileExt == 'onnx' || fileExt == 'gguf' || fileExt == 'bin';
                          
                          String fileSize = '';
                          if (!isDirectory) {
                            try {
                              final size = File(file.path).statSync().size;
                              fileSize = _formatSize(size);
                            } catch (e) {}
                          }
                          
                          return ListTile(
                            leading: Icon(
                              isDirectory ? Icons.folder : (isModel ? Icons.model_training : Icons.insert_drive_file),
                              color: isDirectory ? Colors.blue : (isModel ? Colors.green : Colors.grey),
                              size: 32,
                            ),
                            title: Text(
                              fileName,
                              style: TextStyle(
                                fontWeight: isModel ? FontWeight.bold : FontWeight.normal,
                                color: isModel ? Colors.green : null,
                              ),
                            ),
                            subtitle: isDirectory ? null : Text(fileSize),
                            trailing: isModel
                                ? ElevatedButton.icon(
                                    onPressed: () => _selectModel(file.path),
                                    icon: const Icon(Icons.play_arrow, size: 16),
                                    label: const Text('تشغيل'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                    ),
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
        onPressed: _pickModelDirectly,
        child: const Icon(Icons.add),
        tooltip: 'اختيار نموذج',
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
