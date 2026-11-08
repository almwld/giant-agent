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
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.execute('PRAGMA journal_mode = WAL');
          await db.execute('PRAGMA synchronous = FULL');
        },
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE agent_requests (
              id TEXT PRIMARY KEY, prompt TEXT NOT NULL,
              conversation_id TEXT NOT NULL, sequence INTEGER NOT NULL UNIQUE,
              status TEXT NOT NULL, created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL, started_at TEXT, completed_at TEXT,
              result TEXT, error TEXT, attempts INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute('CREATE INDEX idx_agent_requests_queue ON agent_requests(status, sequence)');
          await db.execute('''
            CREATE TABLE agent_events (
              row_id INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE,
              request_id TEXT, type TEXT NOT NULL, status TEXT NOT NULL,
              payload_json TEXT NOT NULL, created_at TEXT NOT NULL,
              FOREIGN KEY(request_id) REFERENCES agent_requests(id)
            )
          ''');
          await db.execute('CREATE INDEX idx_agent_events_request ON agent_events(request_id, row_id)');
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
}
