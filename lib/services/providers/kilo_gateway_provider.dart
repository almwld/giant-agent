import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Anonymous, zero-cost model access through Kilo's documented free-model tier.
/// No Authorization header, API key, account, or payment details are sent.
class KiloGatewayModel {
  const KiloGatewayModel({required this.id, required this.name, required this.contextWindow});
  final String id;
  final String name;
  final String contextWindow;
}

class KiloGatewayProvider {
  KiloGatewayProvider._();
  static final KiloGatewayProvider instance = KiloGatewayProvider._();

  static const String baseUrl = 'https://ai-gateway.kilo.ai/api/v1';
  static const String defaultModel = 'kilo-auto/free';
  static const Duration requestTimeout = Duration(seconds: 120);
  static const _storage = FlutterSecureStorage();
  static const _modelKey = 'giant_kilo_anonymous_model';

  static const List<KiloGatewayModel> models = [
    KiloGatewayModel(id: 'kilo-auto/free', name: 'Kilo Auto Free · Automatic routing', contextWindow: '256K'),
    KiloGatewayModel(id: 'baidu/ernie-5.5-flash-preview:free', name: 'Baidu ERNIE 5.5 Flash Preview', contextWindow: '1M'),
    KiloGatewayModel(id: 'cohere/north-mini-code:free', name: 'Cohere North Mini Code', contextWindow: '256K'),
    KiloGatewayModel(id: 'dots-studio/dots-3-note-preview:free', name: 'Dots3-Note Preview', contextWindow: '512K'),
    KiloGatewayModel(id: 'liquid/lfm-3-1.7b:free', name: 'Liquid LFM3 1.7B', contextWindow: '256K'),
    KiloGatewayModel(id: 'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free', name: 'NVIDIA Nemotron 3 Nano Omni', contextWindow: '256K'),
    KiloGatewayModel(id: 'nvidia/nemotron-3-ultra-550b-a55b:free', name: 'NVIDIA Nemotron 3 Ultra', contextWindow: '1M'),
    KiloGatewayModel(id: 'nvidia/nemotron-3.5-lightning:free', name: 'NVIDIA Nemotron 3.5 Lightning', contextWindow: '1M'),
    KiloGatewayModel(id: 'nvidia/nemotron-3.5-super-vl:free', name: 'NVIDIA Nemotron 3.5 Super VL', contextWindow: '1M'),
    KiloGatewayModel(id: 'openrouter/free', name: 'OpenRouter Free Router', contextWindow: '200K'),
    KiloGatewayModel(id: 'particle-ai/particle-1:free', name: 'Particle-1', contextWindow: '1M'),
    KiloGatewayModel(id: 'reflection/beam-free', name: 'Reflection Beam Free', contextWindow: '256K'),
    KiloGatewayModel(id: 'stealth/glyph-cluster', name: 'Stealth Glyph Cluster', contextWindow: '256K'),
  ];

  Future<String> getModel() async =>
      (await _storage.read(key: _modelKey)) ?? defaultModel;

  Future<void> setModel(String model) async {
    if (!models.any((item) => item.id == model)) {
      throw ArgumentError.value(model, 'model', 'Model is not in the anonymous-free allowlist.');
    }
    await _storage.write(key: _modelKey, value: model);
  }

  static Uri get chatCompletionsUri =>
      Uri.parse('$baseUrl/chat/completions');

  static String extractText(dynamic decoded) {
    if (decoded is Map) {
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
        if (message is Map) {
          for (final key in ['reasoning_content', 'reasoning', 'output_text']) {
            final value = message[key];
            if (value is String && value.trim().isNotEmpty) return value.trim();
          }
        }
      }
      final error = decoded['error'];
      if (error != null) {
        final message = error is Map ? error['message'] : error;
        throw StateError(message?.toString() ?? 'Gateway inference failed.');
      }
    }
    throw const FormatException('Kilo Gateway returned no readable completion.');
  }

  /// Builds a keyless request. Intentionally never adds Authorization.
  static http.Request buildRequest({
    required String model,
    required String prompt,
    String? systemPrompt,
    int maxTokens = 768,
    double temperature = 0.25,
  }) {
    return http.Request('POST', chatCompletionsUri)
      ..headers['Content-Type'] = 'application/json; charset=utf-8'
      ..body = jsonEncode({
        'model': model,
        'messages': [
          if (systemPrompt != null && systemPrompt.trim().isNotEmpty)
            {'role': 'system', 'content': systemPrompt.trim()},
          {'role': 'user', 'content': prompt.trim()},
        ],
        'max_tokens': maxTokens.clamp(1, 8192),
        'temperature': temperature.clamp(0, 2),
        'stream': false,
      });
  }

  Future<String> generate(
    String prompt, {
    String? systemPrompt,
    int maxTokens = 768,
    double temperature = 0.25,
    bool Function()? isCancelled,
  }) async {
    if (prompt.trim().isEmpty) throw ArgumentError('Prompt cannot be empty.');
    if (isCancelled?.call() == true) throw StateError('Generation cancelled.');
    final client = http.Client();
    var cancellationSent = false;
    final poll = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!cancellationSent && isCancelled?.call() == true) {
        cancellationSent = true;
        client.close();
      }
    });
    try {
      final request = buildRequest(
        model: await getModel(),
        prompt: prompt,
        systemPrompt: systemPrompt,
        maxTokens: maxTokens,
        temperature: temperature,
      );
      final streamed = await client.send(request).timeout(requestTimeout);
      final response = await http.Response.fromStream(streamed).timeout(requestTimeout);
      if (isCancelled?.call() == true) throw StateError('Generation cancelled.');
      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      dynamic decoded;
      try { decoded = jsonDecode(body); } on FormatException {
        throw FormatException('Kilo Gateway returned non-JSON HTTP ${response.statusCode}.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = decoded is Map && decoded['error'] != null
            ? (decoded['error'] is Map ? decoded['error']['message'] : decoded['error']).toString()
            : body.substring(0, body.length > 400 ? 400 : body.length);
        throw StateError('Kilo Gateway HTTP ${response.statusCode}: $detail');
      }
      return extractText(decoded);
    } on TimeoutException {
      throw TimeoutException('Kilo Gateway timed out after ${requestTimeout.inSeconds}s.');
    } finally {
      poll.cancel();
      client.close();
    }
  }

  Future<String> testConnection() => generate(
    'Reply with exactly: OK',
    maxTokens: 24,
    temperature: 0,
  );
}
