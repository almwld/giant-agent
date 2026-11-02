import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/features/assistant/domain/chat_message.dart';
import 'package:giant_agent_x/features/assistant/domain/conversation.dart';

void main() {
  group('ChatMessage persistence mapping', () {
    test('round-trips conversation-scoped message metadata', () {
      final original = ChatMessage(
        id: 'message-1',
        conversationId: 'conversation-1',
        role: MessageRole.assistant,
        content: 'Hello from Giant Agent',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1730000000000),
        status: MessageStatus.sent,
        model: 'openrouter/free',
        attachments: const ['diagram.png', 'notes.txt'],
      );

      final restored = ChatMessage.fromMap(original.toMap());

      expect(restored.id, original.id);
      expect(restored.conversationId, original.conversationId);
      expect(restored.role, original.role);
      expect(restored.content, original.content);
      expect(restored.status, original.status);
      expect(restored.model, original.model);
      expect(restored.attachments, original.attachments);
      expect(restored.createdAt, original.createdAt);
    });
  });

  group('Conversation persistence mapping', () {
    test('round-trips archive and model metadata', () {
      final original = Conversation(
        id: 'conversation-2',
        title: 'Research session',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1730000000000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1730000005000),
        archived: true,
        model: 'gemini-3.8-flash',
      );

      final restored = Conversation.fromMap(original.toMap());

      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.archived, isTrue);
      expect(restored.model, original.model);
      expect(restored.createdAt, original.createdAt);
      expect(restored.updatedAt, original.updatedAt);
    });
  });
}
