import 'package:flutter/services.dart';

class LocalGgufModel {
  final String id, name, path, size;
  final int sizeBytes;
  const LocalGgufModel({required this.id, required this.name, required this.path, required this.size, required this.sizeBytes});
  factory LocalGgufModel.fromMap(Map<dynamic, dynamic> m) => LocalGgufModel(
    id: m['id']?.toString() ?? m['path']?.toString() ?? '',
    name: m['name']?.toString() ?? 'GGUF',
    path: m['path']?.toString() ?? '',
    size: m['size']?.toString() ?? '—',
    sizeBytes: (m['sizeBytes'] as num?)?.toInt() ?? 0,
  );
}

/// One Dart facade for the Android process-wide llama.cpp JNI runtime.
class LlamaService {
  LlamaService._();
  static final LlamaService instance = LlamaService._();
  static const MethodChannel _channel = MethodChannel('giant_agent/llama');

  Future<List<LocalGgufModel>> discoverModels() async {
    final rows = await _channel.invokeMethod<List<dynamic>>('discoverModels') ?? const [];
    return rows.whereType<Map>().map(LocalGgufModel.fromMap).toList(growable: false);
  }
  Future<LocalGgufModel?> importModel() async {
    final row = await _channel.invokeMethod<Map<dynamic, dynamic>>('pickModel');
    if (row == null || row['status'] != 'IMPORTED') return null;
    return LocalGgufModel.fromMap(row);
  }
  Future<bool> loadModel(String path, {int threads = 2}) async =>
      await _channel.invokeMethod<bool>('loadModel', {'path': path, 'threads': threads.clamp(1, 8).toInt()}) ?? false;
  Future<bool> isLoaded() async => await _channel.invokeMethod<bool>('isLoaded') ?? false;
  Future<String> generate(String prompt, {int maxTokens = 256, double temperature = .25}) async {
    if (!await isLoaded()) return 'ERROR: لم يتم تحميل نموذج GGUF محلي.';
    return await _channel.invokeMethod<String>('generate', {
      'prompt': prompt, 'maxTokens': maxTokens.clamp(1, 2048).toInt(),
      'temperature': temperature.clamp(.05, 1.5).toDouble(),
    }) ?? 'ERROR: لم يصل رد من llama.cpp.';
  }
  Future<bool> cancel() async => await _channel.invokeMethod<bool>('cancelGeneration') ?? false;
  Future<void> unload() => _channel.invokeMethod<void>('freeModel');
  Future<String> get version async => await _channel.invokeMethod<String>('version') ?? 'unknown';
}
