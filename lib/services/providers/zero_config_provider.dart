import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Optional keyless conversational provider. It deliberately sends no API key
/// and is not used for tool-calling/agent orchestration.
class ZeroConfigProvider {
  ZeroConfigProvider._();
  static final ZeroConfigProvider instance = ZeroConfigProvider._();

  static const String baseUrl = 'https://text.pollinations.ai/openai';
  static const String defaultModel = 'openai-fast';
  static const Duration requestTimeout = Duration(seconds: 60);

  static String extractText(dynamic decoded) {
    if (decoded is String && decoded.trim().isNotEmpty) return decoded.trim();
    if (decoded is Map<String, dynamic>) {
      final choices = decoded['choices'];
      if (choices is List && choices.isNotEmpty && choices.first is Map) {
        final message = (choices.first as Map)['message'];
        final content = message is Map ? message['content'] : null;
        if (content is String && content.trim().isNotEmpty) return content.trim();
        if (content is List) {
          final text = content.whereType<Map>()
              .map((part) => part['text']?.toString() ?? '')
              .where((part) => part.isNotEmpty).join('\n').trim();
          if (text.isNotEmpty) return text;
        }
      }
      final content = decoded['content'] ?? decoded['text'];
      if (content is String && content.trim().isNotEmpty) return content.trim();
    }
    throw const FormatException('Pollinations returned no readable text.');
  }

  Future<String> generate(
    String prompt, {
    String? systemPrompt,
    int maxTokens = 768,
    double temperature = 0.35,
  }) async {
    final cleanPrompt = prompt.trim();
    if (cleanPrompt.isEmpty) throw ArgumentError('Prompt cannot be empty.');
    final messages = <Map<String, String>>[
      if (systemPrompt != null && systemPrompt.trim().isNotEmpty)
        {'role': 'system', 'content': systemPrompt.trim()},
      {'role': 'user', 'content': cleanPrompt},
    ];
    final client = http.Client();
    try {
      final response = await client.post(
        Uri.parse(baseUrl),
        headers: const {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({
          'model': defaultModel,
          'messages': messages,
          'max_tokens': maxTokens,
          'temperature': temperature,
        }),
      ).timeout(requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = utf8.decode(response.bodyBytes, allowMalformed: true);
        throw StateError('Pollinations HTTP ${response.statusCode}: ${body.substring(0, body.length.clamp(0, 500))}');
      }
      final raw = utf8.decode(response.bodyBytes, allowMalformed: false);
      dynamic decoded;
      try {
        decoded = jsonDecode(raw);
      } on FormatException {
        // The legacy endpoint may return plain text instead of a JSON envelope.
        decoded = raw;
      }
      return extractText(decoded);
    } on TimeoutException {
      throw TimeoutException('انتهت مهلة Pollinations بعد ${requestTimeout.inSeconds} ثانية.');
    } finally {
      client.close();
    }
  }

  Future<String> testConnection() => generate(
    'أجب بكلمة واحدة فقط: مرحباً',
    maxTokens: 32,
    temperature: 0,
  );
}
