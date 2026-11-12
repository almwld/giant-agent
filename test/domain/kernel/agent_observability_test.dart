import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:giant_agent_x/domain/kernel/agent_kernel_store.dart';
import 'package:giant_agent_x/domain/kernel/agent_observability.dart';

Future<AgentKernelStore> _createStore(String path) async {
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
          await db.execute(
            'CREATE INDEX idx_agent_events_request ON agent_events(request_id, row_id)',
          );
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
    directory = await Directory.systemTemp.createTemp('gain-observability-');
  });
  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('conversation timeline uses stable descending cursor pagination', () async {
    final store = await _createStore('${directory.path}/timeline.db');
    await store.enqueue(id: 'request-1', prompt: 'private prompt', conversationId: 'chat-a');
    await store.markRunning('request-1');
    await store.appendRequestEvent({
      'id': 'tool-1',
      'request_id': 'request-1',
      'type': 'tool_started',
      'status': 'running',
      'tool_call_id': 'call-1',
      'timestamp': DateTime.utc(2026, 1, 1).toIso8601String(),
    });
    await store.appendRequestEvent({
      'id': 'tool-2',
      'request_id': 'request-1',
      'type': 'tool_completed',
      'status': 'completed',
      'tool_call_id': 'call-1',
      'duration_ms': 120,
      'timestamp': DateTime.utc(2026, 1, 2).toIso8601String(),
    });
    await store.appendRequestEvent({
      'id': 'tool-3',
      'request_id': 'request-1',
      'type': 'tool_failed',
      'status': 'failed',
      'tool_call_id': 'call-2',
      'duration_ms': 300,
      'timestamp': DateTime.utc(2026, 1, 3).toIso8601String(),
    });
    await store.complete('request-1', 'done');
    await store.enqueue(id: 'request-2', prompt: 'queued', conversationId: 'chat-a');
    await store.enqueue(id: 'other-chat', prompt: 'excluded', conversationId: 'chat-b');

    final first = await store.observabilityEventsForConversation(
      'chat-a',
      limit: 2,
    );
    expect(first.events.map((event) => event.type), ['request_queued', 'request_completed']);
    expect(first.hasMore, isTrue);
    expect(first.nextCursor, isNotNull);

    final second = await store.observabilityEventsForConversation(
      'chat-a',
      limit: 2,
      beforeRowId: first.nextCursor,
    );
    expect(second.events.map((event) => event.id), ['tool-3', 'tool-2']);
    expect(second.hasMore, isTrue);

    final third = await store.observabilityEventsForConversation(
      'chat-a',
      limit: 2,
      beforeRowId: second.nextCursor,
    );
    expect(third.events.map((event) => event.type), ['tool_started', 'request_started']);
    expect(third.hasMore, isTrue);

    final fourth = await store.observabilityEventsForConversation(
      'chat-a',
      limit: 2,
      beforeRowId: third.nextCursor,
    );
    expect(fourth.events.map((event) => event.type), ['request_queued']);
    expect(fourth.hasMore, isFalse);

    final failed = await store.observabilityEventsForConversation(
      'chat-a',
      status: 'failed',
    );
    expect(failed.events.map((event) => event.id), ['tool-3']);
    await store.close();
  });

  test('summary reports request states and distinct tool outcomes without content', () async {
    final store = await _createStore('${directory.path}/summary.db');
    await store.enqueue(id: 'done-1', prompt: 'do not expose me', conversationId: 'chat-a');
    await store.markRunning('done-1');
    await store.appendRequestEvent({
      'id': 'tool-call-1-start',
      'request_id': 'done-1',
      'type': 'tool_started',
      'status': 'running',
      'tool_call_id': 'call-1',
    });
    await store.appendRequestEvent({
      'id': 'tool-call-1-end',
      'request_id': 'done-1',
      'type': 'tool_completed',
      'status': 'completed',
      'tool_call_id': 'call-1',
      'duration_ms': 120,
    });
    await store.appendRequestEvent({
      'id': 'tool-call-2-failed',
      'request_id': 'done-1',
      'type': 'tool_failed',
      'status': 'failed',
      'tool_call_id': 'call-2',
      'duration_ms': 300,
    });
    await store.complete('done-1', 'private result');
    await store.enqueue(id: 'queued-1', prompt: 'queued', conversationId: 'chat-a');
    await store.enqueue(id: 'other-chat', prompt: 'excluded', conversationId: 'chat-b');

    final summary = await store.observabilitySummaryForConversation('chat-a');
    expect(summary.requestCount, 2);
    expect(summary.activeRequests, 1);
    expect(summary.completedRequests, 1);
    expect(summary.failedRequests, 0);
    expect(summary.eventCount, 7);
    expect(summary.toolCallCount, 2);
    expect(summary.toolFailureCount, 1);
    expect(summary.toolSuccessRate, 0.5);
    expect(summary.averageToolLatencyMs, 210);
    expect(summary.eventTypes['tool_failed'], 1);
    expect(summary.toString(), isNot(contains('do not expose me')));
    await store.close();
  });
}
