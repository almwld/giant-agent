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

  @override
  void initState() {
    super.initState();
    _requestPermission();
  }

  Future<void> _requestPermission() async {
    final status = await Permission.storage.request();
    if (status.isGranted) {
      _loadFiles();
    }
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
    }
  }

  Future<void> _pickModel() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['tflite'],
    );
    
    if (result != null) {
      final filePath = result.files.single.path!;
      final fileName = result.files.single.name;
      
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('متصفح الملفات'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _pickModel,
            tooltip: 'اختيار نموذج',
          ),
        ],
      ),
      body: Column(
        children: [
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
                _buildQuickButton('اختيار نموذج', Icons.model_training, _pickModel),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _files.length,
                    itemBuilder: (context, index) {
                      final file = _files[index];
                      final isDirectory = FileSystemEntity.isDirectorySync(file.path);
                      final fileName = file.path.split('/').last;
                      final isModel = fileName.endsWith('.tflite');
                      
                      return ListTile(
                        leading: Icon(
                          isDirectory ? Icons.folder : (isModel ? Icons.model_training : Icons.insert_drive_file),
                          color: isDirectory ? Colors.blue : (isModel ? Colors.green : Colors.grey),
                        ),
                        title: Text(fileName),
                        trailing: isModel
                            ? ElevatedButton(
                                onPressed: () async {
                                  final modelsDir = Directory('/storage/emulated/0/Download/models/');
                                  if (!await modelsDir.exists()) {
                                    await modelsDir.create(recursive: true);
                                  }
                                  final destPath = '/storage/emulated/0/Download/models/$fileName';
                                  await File(file.path).copy(destPath);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('✅ تم نسخ النموذج: $fileName')),
                                  );
                                  Navigator.pop(context, true);
                                },
                                child: const Text('تشغيل'),
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
        onPressed: _pickModel,
        child: const Icon(Icons.add),
        tooltip: 'إضافة نموذج',
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
}
