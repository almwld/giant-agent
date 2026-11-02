class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.archived = false,
    this.model,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool archived;
  final String? model;

  Conversation copyWith({
    String? title,
    DateTime? updatedAt,
    bool? archived,
    String? model,
  }) => Conversation(
    id: id,
    title: title ?? this.title,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    archived: archived ?? this.archived,
    model: model ?? this.model,
  );

  Map<String, Object?> toMap() => {
    'id': id, 'title': title,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'archived': archived ? 1 : 0, 'model': model,
  };

  factory Conversation.fromMap(Map<String, Object?> map) => Conversation(
    id: map['id']! as String,
    title: map['title'] as String? ?? 'محادثة جديدة',
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at']! as int),
    archived: (map['archived'] as int? ?? 0) == 1,
    model: map['model'] as String?,
  );
}
