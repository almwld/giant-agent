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
    }
  }

  Future<void> _selectModel(String path) async {
    final fileName = path.split('/').last;
    if (fileName.endsWith('.tflite') || 
        fileName.endsWith('.onnx') || 
        fileName.endsWith('.gguf')) {
      
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
        const SnackBar(content: Text('⚠️ هذا ليس ملف نموذج صالح')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('متصفح الملفات'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
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
                  title: Text(fileName),
                  trailing: isModel
                      ? ElevatedButton(
                          onPressed: () => _selectModel(file.path),
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
    );
  }
}
