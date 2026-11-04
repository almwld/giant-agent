import '../data/secure_gateway_provider.dart';
import '../data/sqlite_conversation_repository.dart';
import '../domain/ai_provider.dart';
import 'chat_controller.dart';
import 'default_agent_tools.dart';
import 'gateway_settings.dart';
import 'react_agent_provider.dart';

class AssistantFactory {
  AssistantFactory._();

  static ChatController create({
    required GatewaySettings settings,
    AccessTokenProvider? accessTokenProvider,
  }) {
    return ChatController(
      repository: SqliteConversationRepository(),
      provider: ReActAgentProvider(
        delegate: _ConfiguredGatewayProvider(settings, accessTokenProvider: accessTokenProvider),
        tools: createDefaultAgentTools(),
        maxSteps: 8,
      ),
    );
  }
}

class _ConfiguredGatewayProvider implements AiProvider {
  _ConfiguredGatewayProvider(this.settings, {this.accessTokenProvider});
  final GatewaySettings settings;
  final AccessTokenProvider? accessTokenProvider;

  @override
  String get id => 'secure_gateway';

  @override
  Stream<String> generate(AiGenerationRequest request) async* {
    final url = await settings.baseUrl;
    final token = await (accessTokenProvider ?? () => settings.accessToken)();
    final selectedModel = request.model ?? await settings.model;
    final expiry = token == null ? null : GatewaySettings.tokenExpiry(token);
    final tokenExpired = expiry != null && !expiry.isAfter(DateTime.now().toUtc());
    final selectedProvider = await settings.provider;
    final providerApiKey = await settings.providerApiKey;
    if (url.isEmpty || token == null || token.isEmpty) {
      throw StateError('لم يتم إعداد اتصال خادم الذكاء الاصطناعي.');
    }
    if (tokenExpired) {
      throw StateError('انتهت صلاحية جلسة الذكاء الاصطناعي. أعد تسجيل الدخول أو حدّث رمز الوصول.');
    }
    final provider = SecureGatewayProvider(
      baseUrl: url,
      accessTokenProvider: accessTokenProvider ?? () async => token,
      provider: selectedProvider,
      providerApiKey: providerApiKey,
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
