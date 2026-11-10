import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:giant_agent_x/domain/kernel/agent_kernel.dart'
    as durable;
import 'package:giant_agent_x/domain/kernel/agent_kernel_store.dart';
import 'package:giant_agent_x/services/agent_service.dart';

Future<AgentKernelStore> _store(String path) async {
  return AgentKernelStore(
    databaseProvider: () => databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.execute('PRAGMA journal_mode = WAL');
          await db.execute('PRAGMA synchronous = FULL');
        },
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE agent_requests (
              id TEXT PRIMARY KEY,
              prompt TEXT NOT NULL,
              conversation_id TEXT NOT NULL,
              sequence INTEGER NOT NULL UNIQUE,
              status TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              started_at TEXT,
              completed_at TEXT,
              result TEXT,
              error TEXT,
              attempts INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_agent_requests_queue ON agent_requests(status, sequence)',
          );
          await db.execute('''
            CREATE TABLE agent_tasks (
              sequence INTEGER PRIMARY KEY AUTOINCREMENT,
              id TEXT NOT NULL UNIQUE,
              conversation_id TEXT NOT NULL DEFAULT 'global',
              status TEXT NOT NULL,
              payload_json TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE agent_events (
              row_id INTEGER PRIMARY KEY AUTOINCREMENT,
              id TEXT NOT NULL UNIQUE,
              request_id TEXT,
              task_id TEXT,
              type TEXT NOT NULL,
              status TEXT NOT NULL,
              payload_json TEXT NOT NULL,
              created_at TEXT NOT NULL,
              FOREIGN KEY(request_id) REFERENCES agent_requests(id)
            )
          ''');
          await db.execute('CREATE INDEX idx_agent_events_task ON agent_events(task_id, row_id)');
          await db.execute(
            'CREATE INDEX idx_agent_events_request ON agent_events(request_id, row_id)',
          );
          await db.execute("""
            CREATE TRIGGER agent_events_no_update
            BEFORE UPDATE ON agent_events
            BEGIN SELECT RAISE(ABORT, 'agent_events is append-only'); END
          """);
          await db.execute("""
            CREATE TRIGGER agent_events_no_delete
            BEFORE DELETE ON agent_events
            BEGIN SELECT RAISE(ABORT, 'agent_events is append-only'); END
          """);
        },
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('agent-service-durable-');
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('AgentService persists requests and executes them through one FIFO boundary',
      () async {
    final started = <String>[];
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final store = await _store('${directory.path}/service.db');
    final service = AgentService.withExecutor(
      store: store,
      executor: (request) async {
        started.add(request.prompt);
        if (request.prompt == 'first') {
          firstStarted.complete();
          await releaseFirst.future;
        }
        return 'result:${request.prompt}';
      },
    );

    final first = service.runTask('first', conversationId: 'voice');
    await firstStarted.future.timeout(const Duration(seconds: 5));
    final second = service.runTask('second', conversationId: 'chat');
    releaseFirst.complete();

    expect(await first, 'result:first');
    expect(await second, 'result:second');
    expect(started, ['first', 'second']);

    final events = await service.eventsFor(
      (await store.queuedRequests()).isEmpty
          ? (await _requestIdForPrompt(store, 'first'))
          : '',
    );
    expect(events.map((event) => event.type), [
      'request_queued',
      'request_started',
      'request_completed',
    ]);
    await service.disposeForTesting();
  });

  test('runtime subagent lifecycle events are appended to the parent request journal',
      () async {
    final store = await _store('${directory.path}/subagent-events.db');
    final service = AgentService.withExecutor(
      store: store,
      executor: (request) async => 'completed:${request.prompt}',
    );

    await service.runTask('delegate this task', conversationId: 'agent-chat');
    final requestId = await _requestIdForPrompt(store, 'delegate this task');
    await store.appendRequestEvent({
      'id': 'subagent-event-1',
      'request_id': requestId,
      'task_id': 'child-1',
      'type': 'subagent_started',
      'status': 'running',
      'title': 'Explore worker started',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    final events = await service.eventsFor(requestId);
    expect(events.last.type, 'subagent_started');
    expect(events.last.status, 'running');
    expect(events.last.payload['task_id'], 'child-1');
    await service.disposeForTesting();
  });

  test('subagent snapshots are durable and interrupted children are not replayed', () async {
    final store = await _store('${directory.path}/subagent-recovery.db');
    await store.enqueue(id: 'parent-1', prompt: 'parent', conversationId: 'chat-1');
    await store.markRunning('parent-1');
    await store.recordSubagentEvent({
      'id': 'child-event-1',
      'request_id': 'parent-1',
      'session_id': 'chat-1',
      'task_id': 'parent-1_agent_worker',
      'agent_type': 'coder',
      'title': 'Implement feature',
      'task_prompt': 'Implement the requested feature',
      'depends_on': ['parent-1_agent_explore'],
      'type': 'subagent_started',
      'status': 'running',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    final before = await store.subagentsForRequest('parent-1');
    expect(before.single['prompt'], 'Implement the requested feature');
    expect(before.single['status'], 'running');

    expect(await store.reconcileInterruptedSubagents(), 1);
    final after = await store.subagentsForRequest('parent-1');
    expect(after.single['status'], 'interrupted');
    expect(after.single['recovery_requires_explicit_resume'], isTrue);
    expect((await store.taskEvents('parent-1_agent_worker')).last.type,
        'subagent_interrupted_on_restart');
  });

  test('interrupted output is persisted as interrupted, not completed', () async {
    final store = await _store('${directory.path}/interrupted.db');
    late String requestId;
    final service = AgentService.withExecutor(
      store: store,
      executor: (request) async {
        requestId = request.id;
        throw const durable.KernelRequestInterrupted('stopped safely');
      },
    );

    expect(await service.runTask('interrupt me'), 'stopped safely');
    expect((await service.request(requestId))?.status, 'interrupted');
    expect(
      (await service.eventsFor(requestId)).map((event) => event.type),
      ['request_queued', 'request_started', 'request_interrupted'],
    );
    await service.disposeForTesting();
  });

  test('execution exceptions remain failed and are not returned as success',
      () async {
    final store = await _store('${directory.path}/failed.db');
    late String requestId;
    final service = AgentService.withExecutor(
      store: store,
      executor: (request) async {
        requestId = request.id;
        throw StateError('executor exploded');
      },
    );

    await expectLater(
      service.runTask('fail me'),
      throwsA(isA<StateError>()),
    );
    expect((await service.request(requestId))?.status, 'failed');
    expect(
      (await service.eventsFor(requestId)).last.type,
      'request_failed',
    );
    await service.disposeForTesting();
  });
}

Future<String> _requestIdForPrompt(
  AgentKernelStore store,
  String prompt,
) async {
  // Tests use unique request ids and only need to resolve the persisted row.
  // Querying the SQLite table directly avoids exposing an all-requests API.
  final database = await store.database;
  final rows = await database.query(
    'agent_requests',
    columns: ['id'],
    where: 'prompt = ?',
    whereArgs: [prompt],
    limit: 1,
  );
  return rows.single['id']! as String;
}
