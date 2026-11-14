import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Legacy keyless Pollinations endpoint.
///
/// The official Gen API now requires user authorization. This adapter keeps
/// the former public text endpoint as a best-effort, no-key option. Availability
/// and rate limits are controlled by Pollinations and can change independently.
class ZeroConfigProvider {
  ZeroConfigProvider._();
  static final ZeroConfigProvider instance = ZeroConfigProvider._();

  static const String baseUrl = 'https://text.pollinations.ai/openai';
  static const String defaultModel = 'openai-fast';
  static const Duration requestTimeout = Duration(seconds: 90);

  static String extractText(dynamic decoded) {
    if (decoded is String && decoded.trim().isNotEmpty) return decoded.trim();
    if (decoded is Map) {
      final choices = decoded['choices'];
      if (choices is List && choices.isNotEmpty && choices.first is Map) {
        final message = (choices.first as Map)['message'];
        final content = message is Map ? message['content'] : null;
        if (content is String && content.trim().isNotEmpty) return content.trim();
        if (content is List) {
          final value = content.whereType<Map>()
              .map((part) => part['text']?.toString() ?? '')
              .where((part) => part.isNotEmpty).join('\n').trim();
          if (value.isNotEmpty) return value;
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
    bool Function()? isCancelled,
  }) async {
    final cleanPrompt = prompt.trim();
    if (cleanPrompt.isEmpty) throw ArgumentError('Prompt cannot be empty.');
    if (isCancelled?.call() == true) throw const _PollinationsCancelled();
    final client = http.Client();
    var cancellationSent = false;
    final cancellationPoll = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) {
        if (!cancellationSent && isCancelled?.call() == true) {
          cancellationSent = true;
          client.close();
        }
      },
    );
    try {
      final messages = <Map<String, String>>[
        if (systemPrompt != null && systemPrompt.trim().isNotEmpty)
          {'role': 'system', 'content': systemPrompt.trim()},
        {'role': 'user', 'content': cleanPrompt},
      ];
      final request = http.Request('POST', Uri.parse(baseUrl))
        ..headers['Content-Type'] = 'application/json; charset=utf-8'
        ..body = jsonEncode({
          'model': defaultModel,
          'messages': messages,
          'max_tokens': maxTokens.clamp(1, 4096),
          'temperature': temperature.clamp(0, 2),
        });
      final streamed = await client.send(request).timeout(requestTimeout);
      if (isCancelled?.call() == true) {
        streamed.stream.listen((_) {}).cancel();
        throw const _PollinationsCancelled();
      }
      final response = await http.Response.fromStream(streamed).timeout(requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = utf8.decode(response.bodyBytes, allowMalformed: true);
        final detail = body.substring(0, body.length > 400 ? 400 : body.length);
        throw StateError('Pollinations HTTP ${response.statusCode}: $detail');
      }
      if (isCancelled?.call() == true) throw const _PollinationsCancelled();
      final raw = utf8.decode(response.bodyBytes, allowMalformed: false);
      dynamic decoded;
      try {
        decoded = jsonDecode(raw);
      } on FormatException {
        decoded = raw;
      }
      return extractText(decoded);
    } on http.ClientException {
      if (isCancelled?.call() == true) return 'تم إيقاف التوليد.';
      rethrow;
    } on TimeoutException {
      if (isCancelled?.call() == true) return 'تم إيقاف التوليد.';
      throw TimeoutException('انتهت مهلة Pollinations بعد ${requestTimeout.inSeconds} ثانية.');
    } finally {
      cancellationPoll.cancel();
      client.close();
    }
  }

  Future<String> testConnection() => generate(
    'أجب بكلمة واحدة فقط: مرحباً',
    maxTokens: 32,
    temperature: 0,
  );
}

class _PollinationsCancelled implements Exception {
  const _PollinationsCancelled();
  @override
  String toString() => 'تم إلغاء طلب Pollinations.';
}
