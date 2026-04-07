import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ModelDownloader {
  static final List<Map<String, String>> availableModels = [
    {'name': 'Phi-3-mini', 'url': 'https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4_K_M.gguf', 'size': '2.3 GB'},
    {'name': 'TinyLlama', 'url': 'https://huggingface.co/TheBloke/TinyLlama-1.1B-GGUF/resolve/main/tinyllama-1.1b.Q4_K_M.gguf', 'size': '600 MB'},
    {'name': 'Gemma-2B', 'url': 'https://huggingface.co/google/gemma-2b-it-GGUF/resolve/main/gemma-2b-it-q4_K_M.gguf', 'size': '1.5 GB'},
  ];
  
  static Future<bool> downloadModel(String url, String name, Function(double) onProgress) async {
    try {
      final dir = await getExternalStorageDirectory();
      final modelsDir = Directory('${dir?.path}/Download/models/');
      if (!await modelsDir.exists()) await modelsDir.create(recursive: true);
      
      final response = await http.Client().get(Uri.parse(url));
      final total = response.contentLength ?? 0;
      var downloaded = 0;
      final file = File('${modelsDir.path}/$name.gguf');
      final sink = file.openWrite();
      
      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloaded += chunk.length;
        onProgress(downloaded / total);
      }
      await sink.close();
      return true;
    } catch (e) {
      return false;
    }
  }
}
