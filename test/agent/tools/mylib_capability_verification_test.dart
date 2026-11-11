import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:giant_agent_x/domain/harness/evaluator_service.dart';
import 'package:giant_agent_x/services/agent_memory_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('verifies web, task, voice, data-source and slide results', () async {
    final evaluator = EvaluatorService(
      readWorkspaceFile: (path) async => <String, dynamic>{
        'ok': true,
        'path': path,
        'content': '<html><section class="slide active"></section></html>',
      },
    );

    expect((await evaluator.verify('search', 'web_search', const {}, {
      'ok': true, 'results': [{'title': 'Result', 'url': 'https://example.com'}],
    })).passed, isTrue);

    expect((await evaluator.verify('read todos', 'todo_read', const {}, {
      'ok': true, 'tasks': [{'id': 'task-1'}],
    })).passed, isTrue);

    expect((await evaluator.verify('add todo', 'todo_write', const {}, {
      'ok': true, 'task': {'id': 'task-1', 'status': 'pending'},
      'execution_started': false,
    })).passed, isTrue);

    expect((await evaluator.verify('speak', 'generate_speech', const {}, {
      'ok': true, 'played': true, 'saved_audio_file': false,
    })).passed, isTrue);

    expect((await evaluator.verify('voices', 'get_available_voices', const {}, {
      'ok': true, 'voices': [{'name': 'Arabic', 'locale': 'ar'}],
    })).passed, isTrue);

    expect((await evaluator.verify('sources', 'get_data_source', const {}, {
      'ok': true, 'servers': [{'id': 'docs'}],
    })).passed, isTrue);

    expect((await evaluator.verify('source info', 'get_data_source_desc',
      const {'server_id': 'docs'}, {
        'ok': true, 'server': {'id': 'docs'}, 'tools': [], 'resources': [],
      })).passed, isTrue);

    final outline = jsonEncode({'title': 'Demo', 'slides': [{'title': 'One'}]});
    expect((await evaluator.verify('outline', 'generate_slides_outline', const {}, {
      'ok': true, 'outline': outline,
    })).passed, isTrue);

    expect((await evaluator.verify('slides', 'slides_generator',
      const {'path': 'deck.html', 'slides': [{'title': 'One'}]}, {
        'ok': true, 'created_file': {'ok': true, 'path': 'deck.html'},
      })).passed, isTrue);
  });

  test('verifies DMail as local chat recall, not outbound email', () async {
    final evaluator = EvaluatorService(
      readWorkspaceFile: (_) async => const <String, dynamic>{'ok': false},
    );
    final result = await evaluator.verify(
      'recall previous chat',
      'dmail',
      const <String, dynamic>{'query': 'MCP'},
      const <String, dynamic>{
        'ok': true,
        'query': 'MCP',
        'results': <dynamic>[],
        'source': 'local_sqlite_conversation_history',
        'email_sent': false,
      },
    );
    expect(result.passed, isTrue);
  });

  test('verifies structured widget publication', () async {
    final evaluator = EvaluatorService(
      readWorkspaceFile: (_) async => const <String, dynamic>{'ok': false},
    );
    final result = await evaluator.verify(
      'show progress',
      'show_widget',
      const <String, dynamic>{'widget_type': 'progress'},
      const <String, dynamic>{
        'ok': true,
        'widget_id': 'widget_request_1',
        'widget_type': 'progress',
        'title': 'Build progress',
      },
    );
    expect(result.passed, isTrue);
  });

  test('verifies provider-backed media assets without inventing provider output', () async {
    final evaluator = EvaluatorService(
      readWorkspaceFile: (_) async => const <String, dynamic>{'ok': false},
    );
    final result = await evaluator.verify(
      'generate an image',
      'generate_image',
      const <String, dynamic>{'prompt': 'teal sphere'},
      <String, dynamic>{
        'ok': true,
        'provider_id': 'connected-image-provider',
        'assets': <Map<String, dynamic>>[
          <String, dynamic>{
            'mime_type': 'image/png',
            'remote_url': 'https://media.example/image.png',
            'metadata': <String, dynamic>{},
          },
        ],
      },
    );
    expect(result.passed, isTrue);

    final unavailable = await evaluator.verify(
      'generate an image',
      'generate_image',
      const <String, dynamic>{'prompt': 'teal sphere'},
      const <String, dynamic>{
        'ok': false,
        'error': 'No provider is connected.',
        'assets': <dynamic>[],
      },
    );
    expect(unavailable.passed, isFalse);
  });

  test('memory tool verification reads back local SQLite and audit history', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE turns (id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL DEFAULT \'global\', user_text TEXT NOT NULL, assistant_text TEXT NOT NULL, created_at INTEGER NOT NULL)');
          await db.execute('CREATE TABLE facts (id INTEGER PRIMARY KEY AUTOINCREMENT, fact_key TEXT NOT NULL UNIQUE, fact_value TEXT NOT NULL, importance INTEGER NOT NULL DEFAULT 1, updated_at INTEGER NOT NULL)');
          await db.execute('CREATE TABLE fact_edits (id INTEGER PRIMARY KEY AUTOINCREMENT, fact_key TEXT NOT NULL, operation TEXT NOT NULL, previous_value TEXT, new_value TEXT, importance INTEGER, updated_at INTEGER NOT NULL)');
        },
      ),
    );
    final memory = AgentMemoryService.instance;
    memory.useDatabaseForTesting(db);
    final evaluator = EvaluatorService(
      readWorkspaceFile: (_) async => const <String, dynamic>{'ok': false},
    );
    try {
      await memory.remember('theme', 'dark');
      expect((await evaluator.verify('insert', 'memory_space_insert',
        const {'key': 'theme', 'value': 'dark'}, const {'ok': true})).passed, isTrue);

      await memory.updateFact('theme', 'teal');
      expect((await evaluator.verify('update', 'memory_space_update',
        const {'key': 'theme', 'value': 'teal'}, const {'ok': true})).passed, isTrue);

      await memory.deleteFact('theme');
      expect((await evaluator.verify('delete', 'memory_space_delete',
        const {'key': 'theme'}, const {'ok': true})).passed, isTrue);

      expect((await evaluator.verify('history', 'memory_space_edits', const {}, {
        'ok': true, 'facts': [], 'edits': await memory.getFactEdits(),
      })).passed, isTrue);
    } finally {
      await memory.close();
    }
  });
}
