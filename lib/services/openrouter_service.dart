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
  static const _baseUrlName = 'giant_openrouter_base_url';
  static const defaultBaseUrl = 'https://openrouter.ai/api/v1';
  static const defaultModel = 'openai/gpt-4o-mini';

  Future<String?> getApiKey() => _storage.read(key: _keyName);
  Future<String> getBaseUrl() async =>
      (await _storage.read(key: _baseUrlName))?.trim().isNotEmpty == true
          ? (await _storage.read(key: _baseUrlName))!.trim()
          : defaultBaseUrl;
  Future<String> getModel() async =>
      (await _storage.read(key: _modelName))?.trim().isNotEmpty == true
          ? (await _storage.read(key: _modelName))!.trim()
          : defaultModel;
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
    final endpoint = baseUrl.trim().replaceFirst(RegExp(r'/+

    // Accept any non-empty API key string. Do not enforce provider prefixes,
    // character sets, or key-specific formatting in the client. The endpoint
    // will validate the credential and return the authoritative error.
    if (key.isEmpty) {
      throw ArgumentError('أدخل مفتاح API أولاً.');
    }
    if (Uri.tryParse(endpoint)?.hasScheme != true ||
        !{'http', 'https'}.contains(Uri.parse(endpoint).scheme) ||
        Uri.parse(endpoint).host.isEmpty) {
      throw ArgumentError('عنوان API غير صحيح. أدخل عنوان HTTPS متوافقاً مع OpenAI.');
    }
    if (modelId.isEmpty ||
        !RegExp(r'^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.:+-]+$')
            .hasMatch(modelId)) {
      throw ArgumentError(
        'معرّف النموذج غير صحيح. استخدم الصيغة provider/model مثل openai/gpt-4o-mini.',
      );
    }

    await _storage.write(key: _keyName, value: key);
    await _storage.write(key: _modelName, value: modelId);
    await _storage.write(key: _baseUrlName, value: endpoint);
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
    await _storage.delete(key: _baseUrlName);
    await _storage.delete(key: _enabledName);
  }

  Future<String> generate(
    String prompt, {
    int maxTokens = 768,
    double temperature = 0.25,
  }) async {
    final key = (await getApiKey())?.trim();
    if (key == null || key.isEmpty || !await isEnabled()) {
      throw StateError('مزود OpenRouter غير مفعّل أو لا يوجد مفتاح محفوظ.');
    }

    final response = await http
        .post(
          Uri.parse('${await getBaseUrl()}/chat/completions'),
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
            if ((await getBaseUrl()).contains('openrouter.ai')) ...{
              'HTTP-Referer': 'https://github.com/almwld/giant-agent',
              'X-Title': 'Giant Agent',
            },
          },
          body: jsonEncode({
            'model': await getModel(),
            'messages': [
              {'role': 'user', 'content': prompt}
            ],
            'max_tokens': maxTokens,
            'temperature': temperature,
          }),
        )
        .timeout(const Duration(seconds: 90));

    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw StateError(
        'استجابة OpenRouter ليست JSON صالحاً (HTTP ${response.statusCode}). '
        'تحقق من الاتصال وحالة الخدمة ثم أعد المحاولة.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map
          ? (decoded['error'] is Map
              ? decoded['error']['message']?.toString()
              : decoded['error']?.toString())
          : null;
      throw StateError(
        'OpenRouter (${response.statusCode}): '
        '${detail?.trim().isNotEmpty == true ? detail : 'تعذر تنفيذ الطلب.'}',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw StateError('تنسيق استجابة OpenRouter غير متوقع.');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw StateError('لم يُرجع OpenRouter أي إجابة.');
    }
    final firstChoice = choices.first;
    if (firstChoice is! Map) {
      throw StateError('تنسيق اختيار الإجابة من OpenRouter غير صالح.');
    }
    final message = firstChoice['message'];
    if (message is! Map) {
      throw StateError('استجابة OpenRouter لا تحتوي رسالة صالحة.');
    }
    final content = message['content'];
    if (content is String && content.trim().isNotEmpty) {
      return content.trim();
    }
    if (content is List) {
      final text = content
          .whereType<Map>()
          .map((part) => part['text']?.toString() ?? '')
          .where((part) => part.isNotEmpty)
          .join('\n');
      if (text.trim().isNotEmpty) return text.trim();
    }
    throw StateError('استجابة OpenRouter لا تحتوي نصاً قابلاً للعرض.');
  }
}
), '');

    // Accept any non-empty API key string. Do not enforce provider prefixes,
    // character sets, or key-specific formatting in the client. The endpoint
    // will validate the credential and return the authoritative error.
    if (key.isEmpty) {
      throw ArgumentError('أدخل مفتاح API أولاً.');
    }
    if (modelId.isEmpty ||
        !RegExp(r'^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.:+-]+$')
            .hasMatch(modelId)) {
      throw ArgumentError(
        'معرّف النموذج غير صحيح. استخدم الصيغة provider/model مثل openai/gpt-4o-mini.',
      );
    }

    await _storage.write(key: _keyName, value: key);
    await _storage.write(key: _modelName, value: modelId);
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
    await _storage.delete(key: _enabledName);
  }

  Future<String> generate(
    String prompt, {
    int maxTokens = 768,
    double temperature = 0.25,
  }) async {
    final key = (await getApiKey())?.trim();
    if (key == null || key.isEmpty || !await isEnabled()) {
      throw StateError('مزود OpenRouter غير مفعّل أو لا يوجد مفتاح محفوظ.');
    }

    final response = await http
        .post(
          Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
            'HTTP-Referer': 'https://github.com/almwld/giant-agent',
            'X-Title': 'Giant Agent',
          },
          body: jsonEncode({
            'model': await getModel(),
            'messages': [
              {'role': 'user', 'content': prompt}
            ],
            'max_tokens': maxTokens,
            'temperature': temperature,
          }),
        )
        .timeout(const Duration(seconds: 90));

    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw StateError(
        'استجابة OpenRouter ليست JSON صالحاً (HTTP ${response.statusCode}). '
        'تحقق من الاتصال وحالة الخدمة ثم أعد المحاولة.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map
          ? (decoded['error'] is Map
              ? decoded['error']['message']?.toString()
              : decoded['error']?.toString())
          : null;
      throw StateError(
        'OpenRouter (${response.statusCode}): '
        '${detail?.trim().isNotEmpty == true ? detail : 'تعذر تنفيذ الطلب.'}',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw StateError('تنسيق استجابة OpenRouter غير متوقع.');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw StateError('لم يُرجع OpenRouter أي إجابة.');
    }
    final firstChoice = choices.first;
    if (firstChoice is! Map) {
      throw StateError('تنسيق اختيار الإجابة من OpenRouter غير صالح.');
    }
    final message = firstChoice['message'];
    if (message is! Map) {
      throw StateError('استجابة OpenRouter لا تحتوي رسالة صالحة.');
    }
    final content = message['content'];
    if (content is String && content.trim().isNotEmpty) {
      return content.trim();
    }
    if (content is List) {
      final text = content
          .whereType<Map>()
          .map((part) => part['text']?.toString() ?? '')
          .where((part) => part.isNotEmpty)
          .join('\n');
      if (text.trim().isNotEmpty) return text.trim();
    }
    throw StateError('استجابة OpenRouter لا تحتوي نصاً قابلاً للعرض.');
  }
}
