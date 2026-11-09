import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

typedef KernelDatabaseProvider = Future<Database> Function();

class KernelRequestRecord {
  const KernelRequestRecord({
    required this.id,
    required this.prompt,
    required this.sequence,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.conversationId = 'default',
    this.result,
    this.error,
    this.attempts = 0,
  });

  final String id;
  final String prompt;
  final String conversationId;
  final int sequence;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? result;
  final String? error;
  final int attempts;

  factory KernelRequestRecord.fromMap(Map<String, Object?> row) =>
      KernelRequestRecord(
        id: row['id']! as String,
        prompt: row['prompt']! as String,
        conversationId: row['conversation_id']! as String,
        sequence: row['sequence']! as int,
        status: row['status']! as String,
        createdAt: DateTime.parse(row['created_at']! as String),
        updatedAt: DateTime.parse(row['updated_at']! as String),
        result: row['result'] as String?,
        error: row['error'] as String?,
        attempts: row['attempts'] as int? ?? 0,
      );
}

class KernelEventRecord {
  const KernelEventRecord({
    required this.id,
    required this.requestId,
    required this.type,
    required this.status,
    required this.payload,
    required this.createdAt,
  });

  final String id;
  final String? requestId;
  final String type;
  final String status;
  final Map<String, Object?> payload;
  final DateTime createdAt;
}

/// Durable request queue and append-only execution journal.
/// Event rows are inserted only; lifecycle changes update request projections.
class AgentKernelStore {
  AgentKernelStore({KernelDatabaseProvider? databaseProvider})
      : _databaseProvider = databaseProvider ?? _openDefaultDatabase;

  final KernelDatabaseProvider _databaseProvider;
  Database? _database;

  static Future<Database> _openDefaultDatabase() async {
    final directory = await getApplicationSupportDirectory();
    await Directory(directory.path).create(recursive: true);
    return openDatabase(
      '${directory.path}/giant_agent_kernel.db',
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
          CREATE INDEX idx_agent_requests_queue
          ON agent_requests(status, sequence)
        ''');
        await db.execute('''
          CREATE TABLE agent_events (
            row_id INTEGER PRIMARY KEY AUTOINCREMENT,
            id TEXT NOT NULL UNIQUE,
            request_id TEXT,
            type TEXT NOT NULL,
            status TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            created_at TEXT NOT NULL,
            FOREIGN KEY(request_id) REFERENCES agent_requests(id)
          )
        ''');
        await db.execute('''
          CREATE INDEX idx_agent_events_request
          ON agent_events(request_id, row_id)
        ''');
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
    );
  }

  Future<Database> get database async =>
      _database ??= await _databaseProvider();

  Future<void> enqueue({
    required String id,
    required String prompt,
    required String conversationId,
  }) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final nextSequence = (Sqflite.firstIntValue(await txn.rawQuery(
            'SELECT COALESCE(MAX(sequence), 0) + 1 FROM agent_requests',
          )) ??
          1);
      await txn.insert('agent_requests', {
        'id': id,
        'prompt': prompt,
        'conversation_id': conversationId,
        'sequence': nextSequence,
        'status': 'queued',
        'created_at': now,
        'updated_at': now,
        'attempts': 0,
      });
      await _appendEvent(txn, id, 'request_queued', 'pending', {
        'sequence': nextSequence,
      }, now);
    });
  }

  Future<void> reconcileAfterProcessRestart() async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final interrupted = await txn.query(
        'agent_requests',
        columns: ['id'],
        where: "status = 'running'",
      );
      for (final row in interrupted) {
        final id = row['id']! as String;
        await txn.update(
          'agent_requests',
          {
            'status': 'interrupted',
            'error': 'Process ended while request was running; execution was not replayed.',
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        await _appendEvent(txn, id, 'request_interrupted_on_restart',
            'interrupted', const {'replay': false}, now);
      }
    });
  }

  Future<List<KernelRequestRecord>> queuedRequests() async {
    final rows = await (await database).query(
      'agent_requests',
      where: "status = 'queued'",
      orderBy: 'sequence ASC',
    );
    return rows.map(KernelRequestRecord.fromMap).toList(growable: false);
  }

  Future<void> markRunning(String id) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final changed = await txn.update(
        'agent_requests',
        {
          'status': 'running',
          'started_at': now,
          'updated_at': now,
          'attempts': 1,
          'error': null,
        },
        where: "id = ? AND status = 'queued'",
        whereArgs: [id],
      );
      if (changed != 1) throw StateError('Request $id is no longer queued.');
      await _appendEvent(txn, id, 'request_started', 'running', const {}, now);
    });
  }

  Future<void> complete(String id, String result) =>
      _finish(id, 'completed', result: result);

  Future<void> fail(String id, Object error) =>
      _finish(id, 'failed', error: error.toString());

  Future<void> _finish(
    String id,
    String status, {
    String? result,
    String? error,
  }) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final changed = await txn.update(
        'agent_requests',
        {
          'status': status,
          'result': result,
          'error': error,
          'completed_at': now,
          'updated_at': now,
        },
        where: "id = ? AND status = 'running'",
        whereArgs: [id],
      );
      if (changed != 1) throw StateError('Request $id is not running.');
      await _appendEvent(
        txn,
        id,
        status == 'completed' ? 'request_completed' : 'request_failed',
        status,
        {if (error != null) 'error': error},
        now,
      );
    });
  }

  Future<KernelRequestRecord?> getRequest(String id) async {
    final rows = await (await database).query(
      'agent_requests',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : KernelRequestRecord.fromMap(rows.single);
  }

  Future<List<KernelEventRecord>> eventsFor(String requestId) async {
    final rows = await (await database).query(
      'agent_events',
      where: 'request_id = ?',
      whereArgs: [requestId],
      orderBy: 'row_id ASC',
    );
    return rows.map((row) => KernelEventRecord(
      id: row['id']! as String,
      requestId: row['request_id'] as String?,
      type: row['type']! as String,
      status: row['status']! as String,
      payload: (jsonDecode(row['payload_json']! as String) as Map)
          .cast<String, Object?>(),
      createdAt: DateTime.parse(row['created_at']! as String),
    )).toList(growable: false);
  }

  Future<void> _appendEvent(
    Transaction txn,
    String requestId,
    String type,
    String status,
    Map<String, Object?> payload,
    String timestamp,
  ) async {
    await txn.insert('agent_events', {
      'id': '${requestId}_${type}_${DateTime.now().microsecondsSinceEpoch}',
      'request_id': requestId,
      'type': type,
      'status': status,
      'payload_json': jsonEncode(payload),
      'created_at': timestamp,
    });
  }

  Future<void> close() async {
    final db = _database;
    _database = null;
    await db?.close();
  }
}
