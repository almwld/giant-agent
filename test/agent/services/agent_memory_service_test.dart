import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:giant_agent_x/services/agent_memory_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('upgrades legacy v1 memory tables and creates missing facts table',
      () async {
    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE turns (id INTEGER PRIMARY KEY AUTOINCREMENT, user_text TEXT NOT NULL, assistant_text TEXT NOT NULL, created_at INTEGER NOT NULL)',
          );
        },
      ),
    );
    try {
      await AgentMemoryService.migrateSchema(database, 1);
      final columns = await database.rawQuery('PRAGMA table_info(turns)');
      expect(columns.any((column) => column['name'] == 'session_id'), isTrue);
      expect(await database.query('facts'), isEmpty);
      expect(await database.query('assistant_messages'), isEmpty);

      // A second migration pass must be safe for partially upgraded installs.
      await AgentMemoryService.migrateSchema(database, 2);
      expect(await database.query('facts'), isEmpty);
    } finally {
      await database.close();
    }
  });

  test('conversation recall is isolated by session and deletions stay scoped',
      () async {
    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE turns (id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL DEFAULT \'global\', user_text TEXT NOT NULL, assistant_text TEXT NOT NULL, created_at INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE facts (id INTEGER PRIMARY KEY AUTOINCREMENT, fact_key TEXT NOT NULL UNIQUE, fact_value TEXT NOT NULL, importance INTEGER NOT NULL DEFAULT 1, updated_at INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE INDEX turns_session_created_at ON turns(session_id, created_at DESC)',
          );
          await db.execute('''
            CREATE TABLE assistant_messages (
              id TEXT PRIMARY KEY,
              session_id TEXT NOT NULL,
              request_id TEXT,
              role TEXT NOT NULL DEFAULT 'assistant',
              status TEXT NOT NULL,
              content TEXT NOT NULL DEFAULT '',
              error TEXT,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              completed_at INTEGER
            )
          ''');
          await db.execute(
            'CREATE INDEX assistant_messages_session_created_at ON assistant_messages(session_id, created_at DESC)',
          );
          await db.execute(
            'CREATE INDEX assistant_messages_request ON assistant_messages(request_id)',
          );
        },
      ),
    );

    final memory = AgentMemoryService.instance;
    memory.useDatabaseForTesting(database);
    try {
      await memory.saveTurn(
        'أفضل أن تكون الإجابات بالعربية الفصحى',
        'سأستخدم العربية الفصحى في هذه الجلسة.',
        conversationId: 'session-ar',
      );
      await memory.saveTurn(
        'I work on an English project',
        'Second session context.',
        conversationId: 'session-en',
      );

      final arabicContext = await memory.buildContext(
        'العربية الفصحى',
        conversationId: 'session-ar',
      );
      expect(arabicContext, contains('العربية الفصحى'));
      expect(arabicContext, isNot(contains('الجلسة الثانية')));

      expect(
        await memory.buildContext('العربية الفصحى', conversationId: 'session-en'),
        isEmpty,
      );

      await memory.deleteConversationMemory('session-ar');
      expect(
        await memory.buildContext('العربية الفصحى', conversationId: 'session-ar'),
        isEmpty,
      );
      expect(
        await memory.buildContext('English project', conversationId: 'session-en'),
        contains('Second session context'),
      );
    } finally {
      await memory.close();
    }
  });
  test('persists streaming assistant message lifecycle and session isolation', () async {
    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE turns (id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL DEFAULT \'global\', user_text TEXT NOT NULL, assistant_text TEXT NOT NULL, created_at INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE facts (id INTEGER PRIMARY KEY AUTOINCREMENT, fact_key TEXT NOT NULL UNIQUE, fact_value TEXT NOT NULL, importance INTEGER NOT NULL DEFAULT 1, updated_at INTEGER NOT NULL)',
          );
          await db.execute('''
            CREATE TABLE assistant_messages (
              id TEXT PRIMARY KEY,
              session_id TEXT NOT NULL,
              request_id TEXT,
              role TEXT NOT NULL DEFAULT 'assistant',
              status TEXT NOT NULL,
              content TEXT NOT NULL DEFAULT '',
              error TEXT,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              completed_at INTEGER
            )
          ''');
          await db.execute(
            'CREATE INDEX assistant_messages_session_created_at ON assistant_messages(session_id, created_at DESC)',
          );
          await db.execute(
            'CREATE INDEX assistant_messages_request ON assistant_messages(request_id)',
          );
        },
      ),
    );

    final memory = AgentMemoryService.instance;
    memory.useDatabaseForTesting(database);
    try {
      await memory.beginAssistantMessage(
        id: 'message-1',
        conversationId: 'session-a',
        requestId: 'request-a',
      );
      await memory.appendAssistantDelta('message-1', 'Hello ');
      await memory.appendAssistantDelta('message-1', 'world');
      final streaming = await memory.assistantMessageById('message-1');
      expect(streaming?['status'], 'streaming');
      expect(streaming?['content'], 'Hello world');

      await memory.finishAssistantMessage(
        id: 'message-1',
        status: 'complete',
        content: 'Hello world!',
      );
      final completed = await memory.assistantMessageById('message-1');
      expect(completed?['status'], 'complete');
      expect(completed?['content'], 'Hello world!');

      await memory.beginAssistantMessage(
        id: 'message-2',
        conversationId: 'session-b',
        requestId: 'request-b',
      );
      await memory.appendAssistantDelta('message-2', 'partial answer');
      await memory.finishAssistantMessage(
        id: 'message-2',
        status: 'interrupted',
        error: 'cancelled by user',
      );
      final interrupted = await memory.assistantMessageById('message-2');
      expect(interrupted?['status'], 'interrupted');
      expect(interrupted?['content'], 'partial answer');

      expect(
        (await memory.assistantMessagesForConversation('session-a')).single['id'],
        'message-1',
      );
      await memory.deleteConversationMemory('session-a');
      expect(await memory.assistantMessagesForConversation('session-a'), isEmpty);
      expect(await memory.assistantMessageById('message-2'), isNotNull);
    } finally {
      await memory.close();
    }
  });

}
