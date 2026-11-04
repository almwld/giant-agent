import 'chat_message.dart';
import 'conversation.dart';

abstract interface class ConversationRepository {
  Future<List<Conversation>> listConversations({bool includeArchived = false});
  Future<Conversation?> getConversation(String id);
  Future<void> saveConversation(Conversation conversation);
  Future<void> deleteConversation(String id);
  Future<List<ChatMessage>> getMessages(String conversationId);
  Future<void> saveMessage(ChatMessage message);
  Future<void> updateMessage(ChatMessage message);
  Future<void> deleteMessages(String conversationId);
  Future<List<Conversation>> searchConversations(String query);
}
