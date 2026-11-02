import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../domain/ai_provider.dart';
import '../domain/chat_attachment.dart';
import '../domain/chat_message.dart';
import '../domain/conversation.dart';
import '../domain/conversation_repository.dart';

class ChatController extends ChangeNotifier {
  ChatController({
    required ConversationRepository repository,
    required AiProvider provider,
    this.model,
  }) : _repository = repository, _provider = provider;

  final ConversationRepository _repository;
  final AiProvider _provider;
  final String? model;

  List<Conversation> conversations = [];
  List<ChatMessage> messages = [];
  String? activeConversationId;
  bool isGenerating = false;
  String? lastError;
  StreamSubscription<String>? _generation;
  Completer<void>? _generationCompletion;
  ChatMessage? _activeAssistantMessage;

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  Future<void> initialize() async {
    conversations = await _repository.listConversations();
    if (conversations.isNotEmpty) {
      await openConversation(conversations.first.id);
    } else {
      await createConversation();
    }
    notifyListeners();
  }

  Future<void> createConversation() async {
    final now = DateTime.now();
    final conversation = Conversation(
      id: _newId(),
      title: 'محادثة جديدة',
      createdAt: now,
      updatedAt: now,
      model: model,
    );
    await _repository.saveConversation(conversation);
    activeConversationId = conversation.id;
    messages = [];
    conversations = await _repository.listConversations();
    lastError = null;
    notifyListeners();
  }

  Future<void> openConversation(String id) async {
    await cancelGeneration();
    final conversation = await _repository.getConversation(id);
    if (conversation == null) return;
    activeConversationId = id;
    messages = await _repository.getMessages(id);
    lastError = null;
    notifyListeners();
  }

  Future<void> send(
    String text, {
    List<ChatAttachment> attachments = const [],
  }) async {
    final content = text.trim();
    if ((content.isEmpty && attachments.isEmpty) || isGenerating) return;
    var conversationId = activeConversationId;
    if (conversationId == null) {
      await createConversation();
      conversationId = activeConversationId;
    }
    if (conversationId == null) return;

    final now = DateTime.now();
    final userMessage = ChatMessage(
      id: _newId(),
      conversationId: conversationId,
      role: MessageRole.user,
      content: content,
      createdAt: now,
      attachments: attachments.map((a) => a.name).toList(),
    );
    messages = [...messages, userMessage];
    await _repository.saveMessage(userMessage);

    final userMessageCount = messages.where((m) => m.role == MessageRole.user).length;
    if (userMessageCount == 1) {
      final title = content.isEmpty ? 'مرفقات جديدة' :
          (content.length > 48 ? '${content.substring(0, 48)}…' : content);
      final current = await _repository.getConversation(conversationId);
      if (current != null) {
        await _repository.saveConversation(current.copyWith(title: title, updatedAt: now));
      }
    }

    final assistant = ChatMessage(
      id: _newId(),
      conversationId: conversationId,
      role: MessageRole.assistant,
      content: '',
      createdAt: DateTime.now(),
      status: MessageStatus.streaming,
      model: model,
    );
    messages = [...messages, assistant];
    _activeAssistantMessage = assistant;
    isGenerating = true;
    lastError = null;
    final completion = Completer<void>();
    _generationCompletion = completion;
    notifyListeners();

    try {
      final history = messages
          .where((m) => m.id != assistant.id && m.status != MessageStatus.failed)
          .toList();
      final stream = _provider.generate(AiGenerationRequest(
        conversationId: conversationId,
        messages: history,
        model: model,
        attachments: attachments,
      ));
      _generation = stream.listen(
        (delta) {
          final current = _activeAssistantMessage;
          if (current == null || delta.isEmpty) return;
          _activeAssistantMessage = current.copyWith(
            content: current.content + delta,
            status: MessageStatus.streaming,
          );
          _replaceMessage(_activeAssistantMessage!);
          notifyListeners();
        },
        onError: (Object error, StackTrace stack) {
          if (!completion.isCompleted) completion.completeError(error, stack);
        },
        onDone: () {
          if (!completion.isCompleted) completion.complete();
        },
        cancelOnError: true,
      );
      await completion.future;
      final completed = _activeAssistantMessage;
      if (completed != null) {
        final saved = completed.copyWith(status: MessageStatus.sent);
        _replaceMessage(saved);
        await _repository.saveMessage(saved);
      }
    } catch (error) {
      lastError = error.toString();
      final failed = _activeAssistantMessage;
      if (failed != null) {
        final updated = failed.copyWith(status: MessageStatus.failed, error: lastError);
        _replaceMessage(updated);
        await _repository.saveMessage(updated);
      }
    } finally {
      isGenerating = false;
      _activeAssistantMessage = null;
      _generation = null;
      _generationCompletion = null;
      conversations = await _repository.listConversations();
      notifyListeners();
    }
  }

  void _replaceMessage(ChatMessage message) {
    messages = messages.map((m) => m.id == message.id ? message : m).toList();
  }

  Future<void> cancelGeneration() async {
    final subscription = _generation;
    _generation = null;
    if (subscription != null) await subscription.cancel();
    final completion = _generationCompletion;
    if (completion != null && !completion.isCompleted) completion.complete();
    _generationCompletion = null;
    final active = _activeAssistantMessage;
    if (active != null) {
      final cancelled = active.copyWith(status: MessageStatus.cancelled);
      _replaceMessage(cancelled);
      await _repository.saveMessage(cancelled);
    }
    _activeAssistantMessage = null;
    isGenerating = false;
    notifyListeners();
  }

  Future<void> retryLast() async {
    if (isGenerating) return;
    final failedIndex = messages.lastIndexWhere(
      (m) => m.role == MessageRole.assistant && m.status == MessageStatus.failed,
    );
    if (failedIndex < 0) return;
    final userIndex = messages.lastIndexWhere(
      (m) => m.role == MessageRole.user && m.createdAt.isBefore(messages[failedIndex].createdAt),
    );
    if (userIndex < 0) return;
    final prompt = messages[userIndex].content;
    final conversationId = messages[userIndex].conversationId;
    final restored = messages.take(userIndex).toList();
    await _repository.deleteMessages(conversationId);
    for (final message in restored) {
      await _repository.saveMessage(message);
    }
    messages = restored;
    notifyListeners();
    await send(prompt);
  }

  Future<void> deleteActiveConversation() async {
    final id = activeConversationId;
    if (id == null) return;
    await cancelGeneration();
    await _repository.deleteConversation(id);
    conversations = await _repository.listConversations();
    activeConversationId = null;
    messages = [];
    if (conversations.isNotEmpty) {
      await openConversation(conversations.first.id);
    } else {
      await createConversation();
    }
  }

  Future<List<Conversation>> search(String query) =>
      _repository.searchConversations(query);

  @override
  void dispose() {
    _generation?.cancel();
    super.dispose();
  }
}
