import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

  /// Kept for compatibility with older UI code. The endpoint is fixed.
  Future<String> getBaseUrl() async => defaultBaseUrl;

  Future<bool> hasLegacyNonOpenRouterEndpoint() async {
    final stored = (await _storage.read(key: _legacyBaseUrlName))?.trim();
    if (stored == null || stored.isEmpty) return false;
    return !isOfficialBaseUrl(stored);
  }

  static bool isOfficialBaseUrl(String value) {
    final endpoint = Uri.tryParse(value.trim());
    return endpoint != null &&
        endpoint.scheme == 'https' &&
        endpoint.host.toLowerCase() == 'openrouter.ai' &&
        endpoint.path.replaceFirst(RegExp(r'/+$'), '') == '/api/v1' &&
        !endpoint.hasQuery &&
        !endpoint.hasFragment &&
        endpoint.userInfo.isEmpty &&
        (endpoint.hasPort == false || endpoint.port == 443);
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
    if (key.isEmpty) throw ArgumentError('أدخل مفتاح OpenRouter أولاً.');
    if (!isOfficialBaseUrl(baseUrl)) {
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
    if (!isOfficialBaseUrl(baseUrl)) {
      throw ArgumentError('OpenRouter endpoint must be https://openrouter.ai/api/v1');
    }
    return Uri.parse('$defaultBaseUrl/chat/completions');
  }

  /// Decode JSON from raw response bytes without relying on a server charset header.
  static dynamic decodeJsonResponse(List<int> bodyBytes) {
    return jsonDecode(utf8.decode(bodyBytes, allowMalformed: false));
  }

  static String extractText(Map<String, dynamic> decoded) {
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw StateError('لم يُرجع OpenRouter أي اختيار للإجابة.');
    }
    final message = (choices.first as Map)['message'];
    if (message is! Map) {
      throw StateError('استجابة OpenRouter لا تحتوي رسالة صالحة.');
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
    throw StateError('استجابة OpenRouter لا تحتوي نصاً قابلاً للعرض.');
  }


  /// Sends an image to a vision-capable OpenRouter model using the standard
  /// OpenAI multimodal content format. The selected model must support vision.
  Future<String> generateWithImage(
    File image, {
    required String prompt,
    int maxTokens = 1024,
    double temperature = 0.2,
  }) async {
    if (!await image.exists()) throw FileSystemException('Image does not exist.', image.path);
    final bytes = await image.readAsBytes();
    if (bytes.isEmpty || bytes.length > 12 * 1024 * 1024) {
      throw FileSystemException('Image must be between 1 byte and 12 MB.', image.path);
    }
    final key = (await getApiKey())?.trim();
    if (key == null || key.isEmpty || !await isEnabled()) {
      throw StateError('OpenRouter غير مفعّل أو لا يوجد مفتاح محفوظ.');
    }
    final extension = image.path.toLowerCase().split('.').last;
    final mime = switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };
    final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
    final client = http.Client();
    try {
      final request = http.Request('POST', chatCompletionsUri(defaultBaseUrl))
        ..followRedirects = false
        ..headers.addAll({
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json; charset=utf-8',
          'HTTP-Referer': 'https://github.com/almwld/giant-agent',
          'X-Title': 'Giant Agent',
        })
        ..body = jsonEncode({
          'model': await getModel(),
          'messages': [{
            'role': 'user',
            'content': [
              {'type': 'text', 'text': prompt},
              {'type': 'image_url', 'image_url': {'url': dataUrl}},
            ],
          }],
          'max_tokens': maxTokens,
          'temperature': temperature,
        });
      final response = await client.send(request).then((streamed) {
        if (streamed.isRedirect) {
          throw StateError('رفض OpenRouter إعادة توجيه طلب الصورة (HTTP ${streamed.statusCode}).');
        }
        return http.Response.fromStream(streamed);
      }).timeout(requestTimeout);
      final dynamic decoded;
      try {
        decoded = decodeJsonResponse(response.bodyBytes);
      } on FormatException {
        throw StateError('أعاد OpenRouter استجابة غير JSON (HTTP ${response.statusCode}).');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = decoded is Map
            ? (decoded['error'] is Map
                ? decoded['error']['message']?.toString()
                : decoded['error']?.toString())
            : null;
        throw StateError('OpenRouter vision HTTP ${response.statusCode}: ${detail ?? 'تعذر تحليل الصورة.'}');
      }
      if (decoded is! Map<String, dynamic>) throw StateError('تنسيق استجابة OpenRouter غير متوقع.');
      return extractText(decoded);
    } on TimeoutException {
      throw TimeoutException('انتهت مهلة تحليل الصورة عبر OpenRouter.');
    } finally {
      client.close();
    }
  }

  Future<String> generate(
    String prompt, {
    int maxTokens = 768,
    double temperature = 0.25,
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
          'Content-Type': 'application/json; charset=utf-8',
          'HTTP-Referer': 'https://github.com/almwld/giant-agent',
          'X-Title': 'Giant Agent',
        })
        ..body = jsonEncode({
          'model': await getModel(),
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
          'max_tokens': maxTokens,
          'temperature': temperature,
        });

      final response = await client.send(request).then((streamed) {
        if (streamed.isRedirect) {
          throw StateError(
            'رفض OpenRouter إعادة توجيه HTTP ${streamed.statusCode}. تحقق من الاتصال أو إعدادات الشبكة.',
          );
        }
        return http.Response.fromStream(streamed);
      }).timeout(requestTimeout);

      final dynamic decoded;
      try {
        decoded = decodeJsonResponse(response.bodyBytes);
      } on FormatException {
        throw StateError(
          'أعاد OpenRouter استجابة غير JSON (HTTP ${response.statusCode}).',
        );
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = decoded is Map
            ? (decoded['error'] is Map
                ? decoded['error']['message']?.toString()
                : decoded['error']?.toString())
            : null;
        throw StateError(
          'OpenRouter HTTP ${response.statusCode}: '
          '${detail?.trim().isNotEmpty == true ? detail : 'تعذر تنفيذ الطلب.'}',
        );
      }
      if (decoded is! Map<String, dynamic>) {
        throw StateError('تنسيق استجابة OpenRouter غير متوقع.');
      }
      return extractText(decoded);
    } on TimeoutException {
      throw TimeoutException(
        'انتهت مهلة OpenRouter بعد ${requestTimeout.inSeconds} ثانية. تحقق من الاتصال أو جرّب نموذجاً أسرع.',
      );
    } finally {
      client.close();
    }
  }
}
