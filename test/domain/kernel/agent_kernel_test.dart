import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:giant_agent_x/domain/kernel/agent_kernel.dart';
import 'package:giant_agent_x/domain/kernel/agent_kernel_store.dart';

Future<Directory> _tempDirectory() => Directory.systemTemp.createTemp('gain-kernel-');

Future<AgentKernelStore> _store(String path) async {
  return AgentKernelStore(
    databaseProvider: () => databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 7,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.rawQuery('PRAGMA journal_mode = WAL');
          await db.execute('PRAGMA synchronous = FULL');
        },
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE agent_requests (
              id TEXT PRIMARY KEY, prompt TEXT NOT NULL,
              conversation_id TEXT NOT NULL, sequence INTEGER NOT NULL UNIQUE,
              status TEXT NOT NULL, created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL, started_at TEXT, completed_at TEXT,
              result TEXT, error TEXT, attempts INTEGER NOT NULL DEFAULT 0,
              task_id TEXT REFERENCES agent_tasks(id) ON DELETE SET NULL
            )
          ''');
          await db.execute('CREATE INDEX idx_agent_requests_queue ON agent_requests(status, sequence)');
          await db.execute('CREATE INDEX idx_agent_requests_task_attempts ON agent_requests(task_id, sequence)');
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
              row_id INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE,
              request_id TEXT, task_id TEXT, type TEXT NOT NULL, status TEXT NOT NULL,
              payload_json TEXT NOT NULL, created_at TEXT NOT NULL,
              FOREIGN KEY(request_id) REFERENCES agent_requests(id)
            )
          ''');
          await db.execute('CREATE INDEX idx_agent_events_request ON agent_events(request_id, row_id)');
          await db.execute('''
            CREATE TABLE agent_battle_cards (
              id TEXT PRIMARY KEY, competitor TEXT NOT NULL,
              product TEXT NOT NULL DEFAULT '', pricing TEXT NOT NULL DEFAULT '',
              source_url TEXT NOT NULL, source_date TEXT NOT NULL,
              evidence_excerpt TEXT NOT NULL, confidence TEXT NOT NULL,
              created_at TEXT NOT NULL, updated_at TEXT NOT NULL
            )
          ''');
          await db.execute('CREATE INDEX idx_agent_battle_cards_competitor ON agent_battle_cards(competitor, source_date DESC)');
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

  test('persists only dated HTTPS competitor evidence and supports deletion', () async {
    final directory = await _tempDirectory();
    final store = await _store('${directory.path}/battle-cards.db');
    try {
      await expectLater(
        store.saveBattleCard({
          'id': 'bad-source',
          'competitor': 'Example',
          'source_url': 'http://example.com',
          'source_date': '2026-11-17',
          'evidence_excerpt': 'This excerpt is long enough for validation.',
          'confidence': 'medium',
        }),
        throwsArgumentError,
      );
      final record = <String, dynamic>{
        'id': 'evidence-1',
        'competitor': 'Example Competitor',
        'product': 'Example Suite',
        'pricing': 'Published annual price observation',
        'source_url': 'https://example.com/pricing',
        'source_date': '2026-11-17',
        'evidence_excerpt': 'The official pricing page lists an annual plan with a published price.',
        'confidence': 'high',
      };
      await store.saveBattleCard(record);
      final saved = await store.getBattleCards();
      expect(saved, hasLength(1));
      expect(saved.single['source_url'], record['source_url']);
      expect(saved.single['confidence'], 'high');
      await store.deleteBattleCard('evidence-1');
      expect(await store.getBattleCards(), isEmpty);
    } finally {
      await store.close();
      await directory.delete(recursive: true);
    }
  });

  test('atomically links task snapshots to every durable execution attempt', () async {
    final directory = await _tempDirectory();
    final store = await _store('${directory.path}/task-link.db');
    final task = <String, dynamic>{
      'id': 'task-linked-1',
      'description': 'durable task relation',
      'conversation_id': 'task-link-test',
      'status': 'running',
      'steps': <Map<String, dynamic>>[
        {'step': 1, 'status': 'running'},
      ],
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final executions = <String>[];
    final kernel = AgentKernel(
      store: store,
      executor: (request) async {
        executions.add(request.id);
        return 'result-${request.id}';
      },
    );
    try {
      await store.saveTask(task);
      for (var attempt = 1; attempt <= 2; attempt++) {
        final requestId = 'task-linked-1-attempt-$attempt';
        task['execution_attempts'] = attempt;
        task['request_id'] = requestId;
        await store.enqueueForTask(
          task: task,
          requestId: requestId,
          prompt: 'run attempt $attempt',
          conversationId: 'task-link-test',
          events: [
            {
              'type': attempt == 1 ? 'task_started' : 'task_resumed',
              'status': 'running',
              'payload': <String, Object?>{'request_id': requestId},
            },
          ],
        );
        final result = await kernel.submit(
          id: requestId,
          prompt: 'run attempt $attempt',
          conversationId: 'task-link-test',
          taskId: 'task-linked-1',
          alreadyEnqueued: true,
        ).timeout(const Duration(seconds: 5));
        expect(result.status, 'completed');
      }

      final db = await store.database;
      final linkedRequests = await db.query(
        'agent_requests',
        columns: ['id', 'task_id', 'status'],
        where: 'task_id = ?',
        whereArgs: ['task-linked-1'],
        orderBy: 'sequence ASC',
      );
      expect(linkedRequests, hasLength(2));
      expect(linkedRequests.map((row) => row['status']),
          everyElement('completed'));
      expect(linkedRequests.map((row) => row['id']), executions);
      final savedTask = (await store.getTasks()).single;
      expect(savedTask['request_id'], 'task-linked-1-attempt-2');
      expect(savedTask['execution_attempts'], 2);
    } finally {
      await kernel.dispose();
      await directory.delete(recursive: true);
    }
  });

  test('executes three concurrently submitted requests in durable FIFO order', () async {
    final directory = await _tempDirectory();
    final store = await _store('${directory.path}/kernel.db');
    final order = <String>[];
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();

    final kernel = AgentKernel(
      store: store,
      executor: (request) async {
        order.add('${request.id}:start');
        if (request.id == 'one') {
          firstStarted.complete();
          await releaseFirst.future;
        }
        order.add('${request.id}:end');
        return 'result-${request.id}';
      },
    );

    try {
      final one = kernel.submit(id: 'one', prompt: 'first');
      await firstStarted.future;
      final two = kernel.submit(id: 'two', prompt: 'second');
      final three = kernel.submit(id: 'three', prompt: 'third');
      releaseFirst.complete();

      final results = await Future.wait([one, two, three]);
      expect(order, [
        'one:start', 'one:end',
        'two:start', 'two:end',
        'three:start', 'three:end',
      ]);
      expect(results.map((item) => item.status), everyElement('completed'));
      expect((await kernel.eventsFor('two')).map((event) => event.type),
          ['request_queued', 'request_started', 'request_completed']);
    } finally {
      await kernel.dispose();
      await directory.delete(recursive: true);
    }
  });

  test('rejects concurrent duplicate request ids without losing the first waiter', () async {
    final directory = await _tempDirectory();
    final kernel = AgentKernel(
      store: await _store('${directory.path}/kernel.db'),
      executor: (request) async => 'completed-${request.id}',
    );
    try {
      final first = kernel.submit(id: 'same-id', prompt: 'first');
      await expectLater(
        kernel.submit(id: 'same-id', prompt: 'duplicate'),
        throwsA(isA<StateError>()),
      );
      final result = await first.timeout(const Duration(seconds: 5));
      expect(result.status, 'completed');
      expect(result.result, 'completed-same-id');
      expect((await kernel.eventsFor('same-id')).map((event) => event.type), [
        'request_queued',
        'request_started',
        'request_completed',
      ]);
    } finally {
      await kernel.dispose();
      await directory.delete(recursive: true);
    }
  });

  test('restores queued requests from SQLite after a process restart', () async {
    final directory = await _tempDirectory();
    final path = '${directory.path}/kernel.db';
    final firstProcessStore = await _store(path);
    await firstProcessStore.enqueue(
      id: 'persisted-one',
      prompt: 'first',
      conversationId: 'restart-test',
    );
    await firstProcessStore.enqueue(
      id: 'persisted-two',
      prompt: 'second',
      conversationId: 'restart-test',
    );
    await firstProcessStore.close();

    final executionOrder = <String>[];
    final allRestored = Completer<void>();
    final restartedKernel = AgentKernel(
      store: await _store(path),
      executor: (request) async {
        executionOrder.add(request.id);
        if (executionOrder.length == 2 && !allRestored.isCompleted) {
          allRestored.complete();
        }
        return 'restored-${request.id}';
      },
    );

    try {
      await restartedKernel.initialize();
      await allRestored.future.timeout(const Duration(seconds: 5));
      expect(executionOrder, ['persisted-one', 'persisted-two']);
      expect((await restartedKernel.request('persisted-one'))?.status, 'completed');
      expect((await restartedKernel.request('persisted-two'))?.status, 'completed');
      expect(
        (await restartedKernel.eventsFor('persisted-two'))
            .map((event) => event.type),
        ['request_queued', 'request_started', 'request_completed'],
      );
    } finally {
      await restartedKernel.dispose();
      await directory.delete(recursive: true);
    }
  });

  test('marks an interrupted running request for reconciliation and never replays it', () async {
    final directory = await _tempDirectory();
    final path = '${directory.path}/kernel.db';
    final oldStore = await _store(path);
    await oldStore.enqueue(id: 'interrupted', prompt: 'may have side effects', conversationId: 'c1');
    await oldStore.markRunning('interrupted');
    await oldStore.close();

    var executions = 0;
    final newKernel = AgentKernel(
      store: await _store(path),
      executor: (_) async {
        executions++;
        return 'should-not-run';
      },
    );
    try {
      await newKernel.initialize();
      final recovered = await newKernel.request('interrupted');
      expect(recovered?.status, 'interrupted');
      expect(executions, 0);
      final events = await newKernel.eventsFor('interrupted');
      expect(events.map((event) => event.type), [
        'request_queued',
        'request_started',
        'request_interrupted_on_restart',
      ]);
    } finally {
      await newKernel.dispose();
      await directory.delete(recursive: true);
    }
  });

  test('retries only explicitly classified transient failures within a durable bound', () async {
    final directory = await _tempDirectory();
    var executions = 0;
    final kernel = AgentKernel(
      store: await _store('${directory.path}/retry.db'),
      executor: (request) async {
        executions++;
        if (executions < 3) {
          throw const RetryableKernelFailure('temporary provider timeout');
        }
        return 'recovered';
      },
    );
    try {
      final result = await kernel.submit(id: 'retry-me', prompt: 'retry safely')
          .timeout(const Duration(seconds: 5));
      expect(executions, 3);
      expect(result.status, 'completed');
      expect(result.attempts, 3);
      expect(result.result, 'recovered');
      expect(
        (await kernel.eventsFor('retry-me')).map((event) => event.type),
        [
          'request_queued',
          'request_started',
          'request_retry_scheduled',
          'request_started',
          'request_retry_scheduled',
          'request_started',
          'request_completed',
        ],
      );
    } finally {
      await kernel.dispose();
      await directory.delete(recursive: true);
    }
  });

  test('blocks a transient retry after a tool side effect has started', () async {
    final directory = await _tempDirectory();
    var executions = 0;
    final store = await _store('${directory.path}/retry-side-effect.db');
    final kernel = AgentKernel(
      store: store,
      executor: (request) async {
        executions++;
        await store.appendRequestEvent({
          'id': 'tool-started-$executions',
          'request_id': request.id,
          'type': 'tool_call_started',
          'status': 'running',
        });
        throw const RetryableKernelFailure('provider timeout after tool');
      },
    );
    try {
      final result = await kernel.submit(id: 'unsafe-retry', prompt: 'may have side effects')
          .timeout(const Duration(seconds: 5));
      expect(executions, 1);
      expect(result.status, 'failed');
      expect(result.attempts, 1);
      final events = await kernel.eventsFor('unsafe-retry');
      expect(events.map((event) => event.type), contains('request_retry_blocked_after_side_effect'));
    } finally {
      await kernel.dispose();
      await directory.delete(recursive: true);
    }
  });

  test('marks a transient failure terminal after the third attempt', () async {
    final directory = await _tempDirectory();
    var executions = 0;
    final kernel = AgentKernel(
      store: await _store('${directory.path}/retry-exhausted.db'),
      executor: (_) async {
        executions++;
        throw const RetryableKernelFailure('provider unavailable');
      },
    );
    try {
      final result = await kernel.submit(id: 'retry-exhausted', prompt: 'bounded retry')
          .timeout(const Duration(seconds: 5));
      expect(executions, 3);
      expect(result.status, 'failed');
      expect(result.attempts, 3);
      final events = await kernel.eventsFor('retry-exhausted');
      expect(events.where((event) => event.type == 'request_retry_scheduled'), hasLength(2));
      expect(events.last.type, 'request_failed');
    } finally {
      await kernel.dispose();
      await directory.delete(recursive: true);
    }
  });

  test('does not retry unclassified failures or interruptions', () async {
    final directory = await _tempDirectory();
    var executions = 0;
    final kernel = AgentKernel(
      store: await _store('${directory.path}/no-retry.db'),
      executor: (_) async {
        executions++;
        throw StateError('unclassified failure');
      },
    );
    try {
      final result = await kernel.submit(id: 'no-retry', prompt: 'do not replay')
          .timeout(const Duration(seconds: 5));
      expect(executions, 1);
      expect(result.status, 'failed');
      expect(result.attempts, 1);
      expect((await kernel.eventsFor('no-retry')).map((event) => event.type), [
        'request_queued',
        'request_started',
        'request_failed',
      ]);
    } finally {
      await kernel.dispose();
      await directory.delete(recursive: true);
    }
  });
}
