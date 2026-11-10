import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// OpenRouter-only OpenAI-compatible adapter. Arbitrary base URLs are rejected.
class OpenAICompatibleProvider {
  OpenAICompatibleProvider._();
  static final OpenAICompatibleProvider instance = OpenAICompatibleProvider._();
  static const _storage = FlutterSecureStorage();
  static const _keyName = 'giant_openrouter_api_key';
  static const _modelName = 'giant_openrouter_model';
  static const _enabledName = 'giant_openrouter_enabled';
  static const _legacyBaseUrlName = 'giant_openrouter_base_url';
  static const defaultBaseUrl = 'https://openrouter.ai/api/v1';
  static const defaultModel = 'openai/gpt-4o-mini';
  static const requestTimeout = Duration(seconds: 120);

  Future<String?> getApiKey() => _storage.read(key: _keyName);
  Future<String> getBaseUrl() async => defaultBaseUrl;
  Future<String> getModel() async {
    final value = (await _storage.read(key: _modelName))?.trim();
    return value == null || value.isEmpty ? defaultModel : value;
  }
  Future<bool> isEnabled() async =>
      (await _storage.read(key: _enabledName)) == 'true' &&
      (await getApiKey())?.trim().isNotEmpty == true;

  Future<void> configure({
    required String apiKey,
    required String model,
    String baseUrl = defaultBaseUrl,
    bool enable = true,
  }) async {
    final key = apiKey.trim();
    final modelId = model.trim();
    final endpoint = Uri.tryParse(baseUrl.trim());
    if (key.isEmpty) throw ArgumentError('أدخل مفتاح OpenRouter أولاً.');
    if (endpoint == null || endpoint.scheme != 'https' ||
        endpoint.host.toLowerCase() != 'openrouter.ai' ||
        endpoint.path.replaceFirst(RegExp(r'/+$'), '') != '/api/v1' ||
        endpoint.hasQuery || endpoint.hasFragment) {
      throw ArgumentError('يُسمح بعنوان OpenRouter الرسمي فقط: $defaultBaseUrl');
    }
    if (modelId.isEmpty) throw ArgumentError('أدخل معرّف نموذج OpenRouter.');
    await _storage.write(key: _keyName, value: key);
    await _storage.write(key: _modelName, value: modelId);
    await _storage.delete(key: _legacyBaseUrlName);
    await _storage.write(key: _enabledName, value: enable ? 'true' : 'false');
  }

  Future<void> setEnabled(bool enabled) async {
    if (enabled && (await getApiKey())?.trim().isNotEmpty != true) {
      throw StateError('احفظ مفتاح OpenRouter أولاً.');
    }
    await _storage.write(key: _enabledName, value: enabled ? 'true' : 'false');
  }
  Future<void> disconnect() async {
    await _storage.delete(key: _keyName);
    await _storage.delete(key: _modelName);
    await _storage.delete(key: _legacyBaseUrlName);
    await _storage.delete(key: _enabledName);
  }

  static Uri chatCompletionsUri(String baseUrl) {
    final endpoint = Uri.parse(baseUrl);
    if (endpoint.scheme != 'https' || endpoint.host.toLowerCase() != 'openrouter.ai' ||
        endpoint.path.replaceFirst(RegExp(r'/+$'), '') != '/api/v1') {
      throw ArgumentError('OpenRouter endpoint must be https://openrouter.ai/api/v1');
    }
    return Uri.parse('$defaultBaseUrl/chat/completions');
  }

  static String extractText(Map<String, dynamic> decoded) {
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw StateError('لم يُرجع OpenRouter أي اختيار للإجابة.');
    }
    final message = (choices.first as Map)['message'];
    if (message is! Map) throw StateError('استجابة OpenRouter لا تحتوي رسالة صالحة.');
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

  Future<String> generate(String prompt, {
    int maxTokens = 768, double temperature = 0.25,
  }) async {
    final key = (await getApiKey())?.trim();
    if (key == null || key.isEmpty || !await isEnabled()) {
      throw StateError('OpenRouter غير مفعّل أو لا يوجد مفتاح محفوظ.');
    }
    final client = http.Client();
    try {
      final request = http.Request('POST', chatCompletionsUri(defaultBaseUrl))
        ..followRedirects = false
        ..headers.addAll({
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
          'HTTP-Referer': 'https://github.com/almwld/giant-agent',
          'X-Title': 'Giant Agent',
        })
        ..body = jsonEncode({
          'model': await getModel(),
          'messages': [{'role': 'user', 'content': prompt}],
          'max_tokens': maxTokens,
          'temperature': temperature,
        });
      final streamed = await client.send(request).timeout(requestTimeout);
      if (streamed.isRedirect) {
        throw StateError('رفض OpenRouter إعادة توجيه HTTP ${streamed.statusCode}. تحقق من الاتصال أو إعدادات الشبكة.');
      }
      final response = await http.Response.fromStream(streamed).timeout(requestTimeout);
      final dynamic decoded;
      try { decoded = jsonDecode(response.body); }
      on FormatException {
        throw StateError('أعاد OpenRouter استجابة غير JSON (HTTP ${response.statusCode}).');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = decoded is Map
            ? (decoded['error'] is Map ? decoded['error']['message']?.toString() : decoded['error']?.toString())
            : null;
        throw StateError('OpenRouter HTTP ${response.statusCode}: ${detail?.trim().isNotEmpty == true ? detail : 'تعذر تنفيذ الطلب.'}');
      }
      if (decoded is! Map<String, dynamic>) throw StateError('تنسيق استجابة OpenRouter غير متوقع.');
      return extractText(decoded);
    } on TimeoutException {
      throw TimeoutException('انتهت مهلة OpenRouter بعد ${requestTimeout.inSeconds} ثانية. تحقق من الاتصال أو جرّب نموذجاً أسرع.');
    } finally {
      client.close();
    }
  }
}
