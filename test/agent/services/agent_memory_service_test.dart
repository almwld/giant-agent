import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:giant_agent_x/services/agent_memory_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('conversation recall is isolated by session and deletions stay scoped',
      () async {
    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 3,
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
        'أعمل على مشروع باللغة الإنجليزية',
        'هذا سياق مستقل للجلسة الثانية.',
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
        await memory.buildContext('الإنجليزية', conversationId: 'session-en'),
        contains('الجلسة الثانية'),
      );
    } finally {
      await memory.close();
    }
  });
}
