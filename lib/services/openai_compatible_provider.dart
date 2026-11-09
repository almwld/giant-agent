import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Provider adapter for any OpenAI-compatible chat-completions endpoint.
/// Supports OpenRouter and other compatible services through a configurable Base URL.
class OpenAICompatibleProvider {
  OpenAICompatibleProvider._();
  static final OpenAICompatibleProvider instance = OpenAICompatibleProvider._();
  static const _storage = FlutterSecureStorage();
  static const _keyName = 'giant_openrouter_api_key';
  static const _modelName = 'giant_openrouter_model';
  static const _enabledName = 'giant_openrouter_enabled';
  static const _baseUrlName = 'giant_openrouter_base_url';
  static const defaultBaseUrl = 'https://openrouter.ai/api/v1';
  static const defaultModel = 'openai/gpt-4o-mini';

  Future<String?> getApiKey() => _storage.read(key: _keyName);

  Future<String> getBaseUrl() async {
    final value = (await _storage.read(key: _baseUrlName))?.trim();
    return value == null || value.isEmpty ? defaultBaseUrl : value;
  }

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
    final endpoint = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');

    if (key.isEmpty) throw ArgumentError('أدخل مفتاح API أولاً.');
    final uri = Uri.tryParse(endpoint);
    if (uri == null ||
        !uri.hasScheme ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw ArgumentError('عنوان API غير صحيح. أدخل عنواناً متوافقاً مع OpenAI.');
    }
    if (modelId.isEmpty) throw ArgumentError('أدخل معرّف النموذج.');

    await _storage.write(key: _keyName, value: key);
    await _storage.write(key: _modelName, value: modelId);
    await _storage.write(key: _baseUrlName, value: endpoint);
    await _storage.write(key: _enabledName, value: enable ? 'true' : 'false');
  }

  Future<void> setEnabled(bool enabled) async {
    if (enabled && (await getApiKey())?.trim().isNotEmpty != true) {
      throw StateError('احفظ مفتاح API أولاً.');
    }
    await _storage.write(key: _enabledName, value: enabled ? 'true' : 'false');
  }

  Future<void> disconnect() async {
    await _storage.delete(key: _keyName);
    await _storage.delete(key: _modelName);
    await _storage.delete(key: _baseUrlName);
    await _storage.delete(key: _enabledName);
  }

  /// Builds the standard chat-completions URL without duplicating the path.
  static Uri chatCompletionsUri(String baseUrl) {
    final endpoint = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse(endpoint.endsWith('/chat/completions')
        ? endpoint
        : '$endpoint/chat/completions');
  }

  Future<String> generate(
    String prompt, {
    int maxTokens = 768,
    double temperature = 0.25,
  }) async {
    final key = (await getApiKey())?.trim();
    if (key == null || key.isEmpty || !await isEnabled()) {
      throw StateError('المزوّد الخارجي غير مفعّل أو لا يوجد مفتاح محفوظ.');
    }

    final baseUrl = await getBaseUrl();
    final response = await http
        .post(
          chatCompletionsUri(baseUrl),
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
            if (baseUrl.contains('openrouter.ai')) ...{
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
        'استجابة المزوّد ليست JSON صالحاً (HTTP ${response.statusCode}). '
        'تحقق من عنوان API والاتصال ثم أعد المحاولة.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map
          ? (decoded['error'] is Map
              ? decoded['error']['message']?.toString()
              : decoded['error']?.toString())
          : null;
      throw StateError(
        'API (${response.statusCode}): '
        '${detail?.trim().isNotEmpty == true ? detail : 'تعذر تنفيذ الطلب.'}',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw StateError('تنسيق استجابة المزوّد غير متوقع.');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw StateError('لم يُرجع المزوّد أي إجابة.');
    }
    final firstChoice = choices.first;
    if (firstChoice is! Map) {
      throw StateError('تنسيق اختيار الإجابة غير صالح.');
    }
    final message = firstChoice['message'];
    if (message is! Map) {
      throw StateError('الاستجابة لا تحتوي رسالة صالحة.');
    }
    final content = message['content'];
    if (content is String && content.trim().isNotEmpty) return content.trim();
    if (content is List) {
      final text = content
          .whereType<Map>()
          .map((part) => part['text']?.toString() ?? '')
          .where((part) => part.isNotEmpty)
          .join('\n');
      if (text.trim().isNotEmpty) return text.trim();
    }
    throw StateError('استجابة المزوّد لا تحتوي نصاً قابلاً للعرض.');
  }