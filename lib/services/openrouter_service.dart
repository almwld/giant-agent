import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Optional OpenRouter inference provider. API credentials remain encrypted.
class OpenRouterService {
  OpenRouterService._();
  static final OpenRouterService instance = OpenRouterService._();
  static const _storage = FlutterSecureStorage();
  static const _keyName = 'giant_openrouter_api_key';
  static const _modelName = 'giant_openrouter_model';
  static const _enabledName = 'giant_openrouter_enabled';
  static const defaultModel = 'openai/gpt-4o-mini';

  Future<String?> getApiKey() => _storage.read(key: _keyName);
  Future<String> getModel() async => await _storage.read(key: _modelName) ?? defaultModel;
  Future<bool> isEnabled() async =>
      (await _storage.read(key: _enabledName)) == 'true' &&
      (await getApiKey())?.isNotEmpty == true;

  Future<void> configure({required String apiKey, required String model, bool enable = true}) async {
    final key = apiKey.trim();
    final modelId = model.trim();
    if (!key.startsWith('sk-or-') || key.length < 20) {
      throw const FormatException('أدخل مفتاح OpenRouter صالحاً.');
    }
    if (modelId.isEmpty || !RegExp(r'^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.:-]+$').hasMatch(modelId)) {
      throw const FormatException('معرّف النموذج يجب أن يكون بصيغة provider/model.');
    }
    await _storage.write(key: _keyName, value: key);
    await _storage.write(key: _modelName, value: modelId);
    await _storage.write(key: _enabledName, value: enable ? 'true' : 'false');
  }

  Future<void> setEnabled(bool enabled) async {
    if (enabled && (await getApiKey())?.isNotEmpty != true) {
      throw StateError('احفظ مفتاح OpenRouter أولاً.');
    }
    await _storage.write(key: _enabledName, value: enabled ? 'true' : 'false');
  }

  Future<void> disconnect() async {
    await _storage.delete(key: _keyName);
    await _storage.delete(key: _modelName);
    await _storage.delete(key: _enabledName);
  }

  Future<String> generate(String prompt, {int maxTokens = 768, double temperature = 0.25}) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty || !await isEnabled()) {
      throw StateError('مزود OpenRouter غير مفعّل أو لا يوجد مفتاح محفوظ.');
    }
    final response = await http.post(
      Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer ' + key,
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://github.com/almwld/giant-agent',
        'X-Title': 'Giant Agent',
      },
      body: jsonEncode({
        'model': await getModel(),
        'messages': [{'role': 'user', 'content': prompt}],
        'max_tokens': maxTokens,
        'temperature': temperature,
      }),
    ).timeout(const Duration(seconds: 90));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var detail = response.body;
      try {
        detail = (jsonDecode(response.body) as Map<String, dynamic>)['error']?.toString() ?? detail;
      } catch (_) {}
      throw StateError('OpenRouter (' + response.statusCode.toString() + '): ' + detail);
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = data['choices'] as List<dynamic>? ?? const [];
    if (choices.isEmpty) throw StateError('لم يُرجع OpenRouter أي إجابة.');
    final message = choices.first['message'] as Map<String, dynamic>? ?? {};
    final content = message['content'];
    if (content is String && content.trim().isNotEmpty) return content.trim();
    if (content is List) {
      final text = content.whereType<Map>()
          .map((part) => part['text']?.toString() ?? '')
          .where((part) => part.isNotEmpty).join('\n');
      if (text.trim().isNotEmpty) return text.trim();
    }
    throw StateError('استجابة OpenRouter لا تحتوي نصاً قابلاً للعرض.');
  }
}
