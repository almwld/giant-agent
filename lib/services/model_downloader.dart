import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ModelDownloader {
  static final List<Map<String, String>> availableModels = [
    {'name': 'Phi-3-mini', 'url': 'https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4_K_M.gguf', 'size': '2.3 GB'},
    {'name': 'TinyLlama', 'url': 'https://huggingface.co/TheBloke/TinyLlama-1.1B-GGUF/resolve/main/tinyllama-1.1b.Q4_K_M.gguf', 'size': '600 MB'},
    {'name': 'Gemma-2B', 'url': 'https://huggingface.co/google/gemma-2b-it-GGUF/resolve/main/gemma-2b-it-q4_K_M.gguf', 'size': '1.5 GB'},
  ];

  static Future<bool> downloadModel(String url, String name, Function(double) onProgress) async {
    final client = http.Client();
    File? partial;
    try {
      final directory = await getExternalStorageDirectory();
      if (directory == null) return false;
      final modelsDir = Directory('${directory.path}/Download/models');
      await modelsDir.create(recursive: true);
      final response = await client.send(http.Request('GET', Uri.parse(url)));
      if (response.statusCode < 200 || response.statusCode >= 300) return false;
      final total = response.contentLength ?? 0;
      var downloaded = 0;
      partial = File('${modelsDir.path}/$name.gguf.part');
      final sink = partial.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          downloaded += chunk.length;
          if (total > 0) onProgress(downloaded / total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      final target = File('${modelsDir.path}/$name.gguf');
      if (await target.exists()) await target.delete();
      await partial.rename(target.path);
      onProgress(1);
      return true;
    } catch (_) {
      if (partial != null && await partial.exists()) await partial.delete();
      return false;
    } finally {
      client.close();
    }
  }
}
