import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:io';

class AssistantDatabase {
  AssistantDatabase._();
  static final AssistantDatabase instance = AssistantDatabase._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final dir = await getApplicationSupportDirectory();
    await Directory(dir.path).create(recursive: true);
    _database = await openDatabase(
      '${dir.path}/giant_agent_assistant.db',
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.execute('PRAGMA journal_mode = WAL');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE conversations (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            archived INTEGER NOT NULL DEFAULT 0,
            model TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            conversation_id TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            status TEXT NOT NULL,
            model TEXT,
            error TEXT,
            attachments_json TEXT NOT NULL DEFAULT '',
            FOREIGN KEY(conversation_id) REFERENCES conversations(id)
              ON DELETE CASCADE
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_messages_conversation_time '
          'ON messages(conversation_id, created_at)',
        );
        await db.execute(
          'CREATE INDEX idx_conversations_updated '
          'ON conversations(archived, updated_at)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Future schema changes must be additive and versioned here.
      },
    );
    return _database!;
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
