import 'package:sqflite/sqflite.dart';
import '../domain/chat_message.dart';
import '../domain/conversation.dart';
import '../domain/conversation_repository.dart';
import 'assistant_database.dart';

class SqliteConversationRepository implements ConversationRepository {
  SqliteConversationRepository({AssistantDatabase? database})
      : _database = database ?? AssistantDatabase.instance;

  final AssistantDatabase _database;
  Future<Database> get _db => _database.database;

  @override
  Future<List<Conversation>> listConversations({bool includeArchived = false}) async {
    final rows = await (await _db).query(
      'conversations',
      where: includeArchived ? null : 'archived = 0',
      orderBy: 'updated_at DESC',
    );
    return rows.map(Conversation.fromMap).toList();
  }

  @override
  Future<Conversation?> getConversation(String id) async {
    final rows = await (await _db).query(
      'conversations', where: 'id = ?', whereArgs: [id], limit: 1,
    );
    return rows.isEmpty ? null : Conversation.fromMap(rows.first);
  }

  @override
  Future<void> saveConversation(Conversation conversation) async {
    await (await _db).insert(
      'conversations', conversation.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteConversation(String id) async {
    await (await _db).delete('conversations', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<ChatMessage>> getMessages(String conversationId) async {
    final rows = await (await _db).query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created_at ASC',
    );
    return rows.map(ChatMessage.fromMap).toList();
  }

  @override
  Future<void> saveMessage(ChatMessage message) async {
    await (await _db).insert('messages', message.toMap());
    await (await _db).update(
      'conversations',
      {'updated_at': message.createdAt.millisecondsSinceEpoch},
      where: 'id = ?', whereArgs: [message.conversationId],
    );
  }

  @override
  Future<void> updateMessage(ChatMessage message) async {
    await (await _db).update(
      'messages', message.toMap(), where: 'id = ?', whereArgs: [message.id],
    );
  }

  @override
  Future<void> deleteMessages(String conversationId) async {
    await (await _db).delete(
      'messages', where: 'conversation_id = ?', whereArgs: [conversationId],
    );
  }

  @override
  Future<List<Conversation>> searchConversations(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return listConversations();
    final rows = await (await _db).rawQuery('''
      SELECT DISTINCT c.* FROM conversations c
      LEFT JOIN messages m ON m.conversation_id = c.id
      WHERE c.archived = 0 AND (c.title LIKE ? OR m.content LIKE ?)
      ORDER BY c.updated_at DESC
    ''', ['%$normalized%', '%$normalized%']);
    return rows.map(Conversation.fromMap).toList();
  }
}
