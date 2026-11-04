class ChatSession {
  const ChatSession({required this.id, required this.title, required this.createdAt, required this.updatedAt});
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() => {
    'id': id, 'title': title,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };

  factory ChatSession.fromMap(Map<String, Object?> map) => ChatSession(
    id: map['id'] as String,
    title: map['title'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
  );
}
