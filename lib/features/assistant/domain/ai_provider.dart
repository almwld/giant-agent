import 'chat_attachment.dart';
import 'chat_message.dart';

class AiGenerationRequest {
  const AiGenerationRequest({
    required this.conversationId,
    required this.messages,
    this.model,
    this.attachments = const [],
    this.temperature = 0.7,
    this.maxOutputTokens = 2048,
  });

  final String conversationId;
  final List<ChatMessage> messages;
  final String? model;
  final List<ChatAttachment> attachments;
  final double temperature;
  final int maxOutputTokens;
}

abstract interface class AiProvider {
  String get id;
  Stream<String> generate(AiGenerationRequest request);
}

abstract interface class LocalInferenceEngine {
  String get engineId;
  bool get isReady;
  Stream<String> generate(AiGenerationRequest request);
}
