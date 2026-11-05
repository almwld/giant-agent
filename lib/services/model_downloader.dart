import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ModelDownloader {
  static final List<Map<String, String>> availableModels = [
    {
      'name': 'Phi-3-mini',
      'url': 'https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4_K_M.gguf',
      'size': '2.3 GB',
    },
    {
      'name': 'TinyLlama',
      'url': 'https://huggingface.co/TheBloke/TinyLlama-1.1B-GGUF/resolve/main/tinyllama-1.1b.Q4_K_M.gguf',
      'size': '600 MB',
    },
    {
      'name': 'Gemma-2B',
      'url': 'https://huggingface.co/google/gemma-2b-it-GGUF/resolve/main/gemma-2b-it-q4_K_M.gguf',
      'size': '1.5 GB',
    },
  ];

  static Future<bool> downloadModel(
    String url,
    String name,
    Function(double) onProgress,
  ) async {
    final client = http.Client();
    File? destination;
    IOSink? sink;
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return false;
      final modelsDir = Directory('${dir.path}/Download/models');
      await modelsDir.create(recursive: true);

      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }

      final total = response.contentLength ?? 0;
      if (total <= 0) return false;

      destination = File('${modelsDir.path}/$name.gguf');
      sink = destination.openWrite();
      var downloaded = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloaded += chunk.length;
        onProgress((downloaded / total).clamp(0.0, 1.0));
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (downloaded != total) {
        await destination.delete();
        return false;
      }
      onProgress(1.0);
      return true;
    } catch (_) {
      if (sink != null) {
        await sink.close();
      }
      if (destination != null && await destination.exists()) {
        await destination.delete();
      }
      return false;
    } finally {
      client.close();
    }
  }
}
