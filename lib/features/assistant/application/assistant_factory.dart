import '../data/secure_gateway_provider.dart';
import '../data/sqlite_conversation_repository.dart';
import 'chat_controller.dart';

class AssistantFactory {
  AssistantFactory._();

  static ChatController create({
    required String gatewayBaseUrl,
    required AccessTokenProvider accessTokenProvider,
    String? model,
  }) {
    final repository = SqliteConversationRepository();
    final provider = SecureGatewayProvider(
      baseUrl: gatewayBaseUrl,
      accessTokenProvider: accessTokenProvider,
    );
    return ChatController(
      repository: repository,
      provider: provider,
      model: model,
    );
  }
}
