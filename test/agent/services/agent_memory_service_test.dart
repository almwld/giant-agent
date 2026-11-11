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
      expect(await database.query('fact_edits'), isEmpty);

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
            'CREATE TABLE fact_edits (id INTEGER PRIMARY KEY AUTOINCREMENT, fact_key TEXT NOT NULL, operation TEXT NOT NULL, previous_value TEXT, new_value TEXT, importance INTEGER, updated_at INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE INDEX turns_session_created_at ON turns(session_id, created_at DESC)',
          );
        },
      ),
    );

    final memory = AgentMemoryService.instance;
    memory.useDatabaseForTesting(database);
    try {
      await memory.remember('language', 'Arabic', importance: 3);
      expect(await memory.updateFact('language', 'Modern Standard Arabic', importance: 4), isTrue);
      expect(await memory.updateFact('missing', 'no-op'), isFalse);
      final facts = await memory.getFacts();
      expect(facts.single['fact_value'], 'Modern Standard Arabic');
      expect(await memory.deleteFact('language'), isTrue);
      expect(await memory.deleteFact('missing'), isFalse);
      final edits = await memory.getFactEdits();
      expect(edits.map((edit) => edit['operation']),
          containsAll(['insert', 'update', 'delete']));

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
}
