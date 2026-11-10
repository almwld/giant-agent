import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Native Google Gemini generateContent adapter (not OpenAI-compatible).
class GeminiProvider {
  GeminiProvider._();
  static final GeminiProvider instance = GeminiProvider._();
  static const _storage = FlutterSecureStorage();
  static const _keyName = 'giant_gemini_api_key';
  static const _modelName = 'giant_gemini_model';
  static const _enabledName = 'giant_gemini_enabled';
  static const defaultModel = 'gemini-flash-latest';
  static const requestTimeout = Duration(seconds: 120);

  Future<String?> getApiKey() => _storage.read(key: _keyName);
  Future<String> getModel() async {
    final value = (await _storage.read(key: _modelName))?.trim();
    return value == null || value.isEmpty ? defaultModel : value;
  }
  Future<bool> isEnabled() async =>
      (await _storage.read(key: _enabledName)) == 'true' &&
      (await getApiKey())?.trim().isNotEmpty == true;

  Future<void> configure({
    required String apiKey,
    String model = defaultModel,
    bool enable = true,
  }) async {
    final key = apiKey.trim();
    final modelId = model.trim();
    if (key.isEmpty) throw ArgumentError('أدخل مفتاح Gemini API أولاً.');
    if (modelId.isEmpty || modelId.contains('/') || modelId.contains(':')) {
      throw ArgumentError('أدخل اسم نموذج Gemini فقط، مثل $defaultModel.');
    }
    await _storage.write(key: _keyName, value: key);
    await _storage.write(key: _modelName, value: modelId);
    await _storage.write(key: _enabledName, value: enable ? 'true' : 'false');
  }

  Future<void> setEnabled(bool enabled) async {
    if (enabled && (await getApiKey())?.trim().isNotEmpty != true) {
      throw StateError('احفظ مفتاح Gemini API أولاً.');
    }
    await _storage.write(key: _enabledName, value: enabled ? 'true' : 'false');
  }

  Future<void> disconnect() async {
    await _storage.delete(key: _keyName);
    await _storage.delete(key: _modelName);
    await _storage.delete(key: _enabledName);
  }

  static Uri generateContentUri(String model) {
    final id = model.trim();
    if (id.isEmpty || id.contains('/') || id.contains(':')) {
      throw ArgumentError('Invalid Gemini model id.');
    }
    return Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/$id:generateContent',
    );
  }

  /// Decode JSON from raw response bytes without relying on a server charset header.
  static dynamic decodeJsonResponse(List<int> bodyBytes) {
    return jsonDecode(utf8.decode(bodyBytes, allowMalformed: false));
  }

  static String extractText(Map<String, dynamic> decoded) {
    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty || candidates.first is! Map) {
      final feedback = decoded['promptFeedback'];
      final blockReason = feedback is Map ? feedback['blockReason']?.toString() : null;
      throw StateError(blockReason == null
          ? 'لم يُرجع Gemini إجابة. تحقق من اسم النموذج أو قيود الطلب.'
          : 'رفض Gemini الطلب بسبب سياسة السلامة: $blockReason');
    }
    final content = (candidates.first as Map)['content'];
    final parts = content is Map ? content['parts'] : null;
    if (parts is! List) throw StateError('استجابة Gemini لا تحتوي أجزاء نصية.');
    final text = parts.whereType<Map>()
        .map((part) => part['text']?.toString() ?? '')
        .where((part) => part.isNotEmpty).join('\n').trim();
    if (text.isEmpty) throw StateError('أعاد Gemini إجابة فارغة.');
    return text;
  }

  Future<String> generate(
    String prompt, {
    int maxTokens = 768,
    double temperature = 0.25,
  }) async {
    final key = (await getApiKey())?.trim();
    if (key == null || key.isEmpty || !await isEnabled()) {
      throw StateError('Gemini غير مفعّل أو لا يوجد مفتاح محفوظ.');
    }
    final client = http.Client();
    try {
      final request = http.Request('POST', generateContentUri(await getModel()))
        ..followRedirects = false
        ..headers.addAll({
          'Content-Type': 'application/json; charset=utf-8',
          'x-goog-api-key': key,
        })
        ..body = jsonEncode({
          'contents': [{
            'parts': [{'text': prompt}]
          }],
          'generationConfig': {
            'maxOutputTokens': maxTokens,
            'temperature': temperature,
          },
        });
      final response = await client.send(request).then((streamed) {
        if (streamed.isRedirect) {
          throw StateError('أعاد Google Gemini توجيه HTTP ${streamed.statusCode}. تحقق من عنوان الخدمة والاتصال.');
        }
        return http.Response.fromStream(streamed);
      }).timeout(requestTimeout);
      final dynamic decoded;
      try {
        decoded = decodeJsonResponse(response.bodyBytes);
      } on FormatException {
        throw StateError('أعاد Gemini استجابة غير JSON (HTTP ${response.statusCode}).');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = decoded is Map && decoded['error'] is Map
            ? (decoded['error'] as Map)['message']?.toString()
            : null;
        throw StateError('Gemini HTTP ${response.statusCode}: ${detail?.trim().isNotEmpty == true ? detail : 'تعذر تنفيذ الطلب.'}');
      }
      if (decoded is! Map<String, dynamic>) {
        throw StateError('تنسيق استجابة Gemini غير متوقع.');
      }
      return extractText(decoded);
    } on TimeoutException {
      throw TimeoutException('انتهت مهلة Gemini بعد ${requestTimeout.inSeconds} ثانية. تحقق من الاتصال أو جرّب نموذجاً أسرع.');
    } finally {
      client.close();
    }
  }
}
