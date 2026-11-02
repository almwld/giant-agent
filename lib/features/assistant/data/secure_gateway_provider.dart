import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../domain/ai_provider.dart';

typedef AccessTokenProvider = Future<String?> Function();

class GatewayException implements Exception {
  const GatewayException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

/// Talks only to the application's authenticated gateway. Provider secrets
/// must remain on that server and must never be compiled into this client.
class SecureGatewayProvider implements AiProvider {
  SecureGatewayProvider({
    required this.baseUrl,
    required this.accessTokenProvider,
    required this.provider,
    this.providerApiKey,
    HttpClient? httpClient,
    this.timeout = const Duration(minutes: 3),
  }) : _client = httpClient ?? HttpClient();

  final String baseUrl;
  final AccessTokenProvider accessTokenProvider;
  final String provider;
  final String? providerApiKey;
  final HttpClient _client;
  final Duration timeout;

  @override
  String get id => 'secure_gateway';

  @override
  Stream<String> generate(AiGenerationRequest request) async* {
    final uri = Uri.parse(baseUrl).resolve('/v1/chat/stream');
    if (uri.scheme != 'https' && uri.host != 'localhost' && uri.host != '10.0.2.2') {
      throw const GatewayException('The AI gateway must use HTTPS.');
    }
    final token = await accessTokenProvider();
    if (token == null || token.trim().isEmpty) {
      throw const GatewayException('Authentication is required before using cloud AI.');
    }

    final payload = {
      'conversation_id': request.conversationId,
      'model': request.model,
      'temperature': request.temperature,
      'max_output_tokens': request.maxOutputTokens,
      'input': request.messages.map((m) => {
        'role': m.role.name,
        'content': m.content,
      }).toList(),
      'attachments': request.attachments.map((a) => a.toGatewayMap()).toList(),
      'stream': true,
    };

    final httpRequest = await _client.postUrl(uri).timeout(timeout);
    httpRequest.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
      ..contentType = ContentType.json
      ..set(HttpHeaders.acceptHeader, 'text/event-stream')
      ..set('x-ai-provider', provider);
    final key = providerApiKey?.trim();
    if (key != null && key.isNotEmpty) {
      httpRequest.headers.set('x-provider-api-key', key);
    }
    httpRequest.add(utf8.encode(jsonEncode(payload)));

    final response = await httpRequest.close().timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await utf8.decoder.bind(response).join();
      throw GatewayException(
        response.statusCode == 401
            ? 'انتهت صلاحية جلسة الذكاء الاصطناعي أو أن رمز الوصول غير صالح. حدّث رمز الوصول ثم أعد المحاولة.'
            : (body.isEmpty ? 'AI gateway request failed.' : body),
        statusCode: response.statusCode,
      );
    }

    final lines = response.transform(utf8.decoder).transform(const LineSplitter()).timeout(timeout);
    try {
      await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data.isEmpty || data == '[DONE]') continue;
      final Map<String, dynamic> event;
      try {
        event = jsonDecode(data) as Map<String, dynamic>;
      } on FormatException {
        continue;
      }
      final type = event['type'] as String? ?? '';
      if (type == 'error') {
        throw GatewayException(event['message'] as String? ?? 'Generation failed.');
      }
      final delta = event['delta'] ?? event['text'];
      if (delta is String && delta.isNotEmpty) {
        yield delta;
      } else if (type == 'response.output_text.delta' && event['delta'] is String) {
        yield event['delta'] as String;
      }
      }
    } on TimeoutException {
      throw const GatewayException('انقطع تدفق الاستجابة بسبب عدم وصول بيانات من الخادم في الوقت المحدد.');
    }
  }

  void dispose() => _client.close(force: true);
}
