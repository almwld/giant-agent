enum MessageRole { user, assistant, system }

enum MessageStatus { sending, streaming, sent, failed, cancelled }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.status = MessageStatus.sent,
    this.model,
    this.error,
    this.attachments = const [],
  });

  final String id;
  final String conversationId;
  final MessageRole role;
  final String content;
  final DateTime createdAt;
  final MessageStatus status;
  final String? model;
  final String? error;
  final List<String> attachments;

  ChatMessage copyWith({
    String? content,
    MessageStatus? status,
    String? model,
    String? error,
    List<String>? attachments,
  }) => ChatMessage(
    id: id,
    conversationId: conversationId,
    role: role,
    content: content ?? this.content,
    createdAt: createdAt,
    status: status ?? this.status,
    model: model ?? this.model,
    error: error,
    attachments: attachments ?? this.attachments,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'conversation_id': conversationId,
    'role': role.name,
    'content': content,
    'created_at': createdAt.millisecondsSinceEpoch,
    'status': status.name,
    'model': model,
    'error': error,
    'attachments_json': attachments.join('\n'),
  };

  factory ChatMessage.fromMap(Map<String, Object?> map) => ChatMessage(
    id: map['id']! as String,
    conversationId: map['conversation_id']! as String,
    role: MessageRole.values.firstWhere((e) => e.name == map['role']),
    content: map['content'] as String? ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
    status: MessageStatus.values.firstWhere(
      (e) => e.name == map['status'],
      orElse: () => MessageStatus.sent,
    ),
    model: map['model'] as String?,
    error: map['error'] as String?,
    attachments: (map['attachments_json'] as String? ?? '')
        .split('\n').where((e) => e.isNotEmpty).toList(),
  );
}
