import '../data/secure_gateway_provider.dart';
import '../data/sqlite_conversation_repository.dart';
import '../domain/ai_provider.dart';
import 'chat_controller.dart';
import 'gateway_settings.dart';

class AssistantFactory {
  AssistantFactory._();

  static ChatController create({required GatewaySettings settings}) {
    return ChatController(
      repository: SqliteConversationRepository(),
      provider: _ConfiguredGatewayProvider(settings),
    );
  }
}

class _ConfiguredGatewayProvider implements AiProvider {
  _ConfiguredGatewayProvider(this.settings);
  final GatewaySettings settings;

  @override
  String get id => 'secure_gateway';

  @override
  Stream<String> generate(AiGenerationRequest request) async* {
    final url = await settings.baseUrl;
    final token = await settings.accessToken;
    final selectedModel = request.model ?? await settings.model;
    if (url.isEmpty || token == null || token.isEmpty) {
      throw StateError('لم يتم إعداد اتصال خادم الذكاء الاصطناعي.');
    }
    final provider = SecureGatewayProvider(
      baseUrl: url,
      accessTokenProvider: () async => token,
    );
    try {
      yield* provider.generate(AiGenerationRequest(
        conversationId: request.conversationId,
        messages: request.messages,
        model: selectedModel,
        attachments: request.attachments,
        temperature: request.temperature,
        maxOutputTokens: request.maxOutputTokens,
      ));
    } finally {
      provider.dispose();
    }
  }
}
