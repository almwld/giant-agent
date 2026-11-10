import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      version: 3,
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
            task_id TEXT,
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
        await db.execute('''
          CREATE INDEX idx_agent_events_task
          ON agent_events(task_id, row_id)
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
        await _createTaskTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createTaskTable(db);
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE agent_events ADD COLUMN task_id TEXT');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_agent_events_task ON agent_events(task_id, row_id)');
        }
      },
    );
  }

  Future<Database> get database async =>
      _database ??= await _databaseProvider();

  static Future<void> _createTaskTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS agent_tasks (
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
      CREATE INDEX IF NOT EXISTS idx_agent_tasks_conversation
      ON agent_tasks(conversation_id, sequence)
    ''');
  }

  /// Returns task snapshots in stable creation order.
  Future<List<Map<String, dynamic>>> getTasks() async {
    final rows = await (await database).query(
      'agent_tasks',
      orderBy: 'sequence ASC',
    );
    return rows.map((row) {
      final decoded = jsonDecode(row['payload_json']! as String);
      if (decoded is! Map) {
        throw const FormatException('Stored agent task is not a JSON object.');
      }
      return Map<String, dynamic>.from(decoded);
    }).toList(growable: false);
  }

  Future<void> saveTask(Map<String, dynamic> task) async {
    final id = task['id']?.toString() ?? '';
    if (id.isEmpty) throw ArgumentError.value(task, 'task', 'Task id is required.');
    final now = DateTime.now().toUtc().toIso8601String();
    final createdAt = task['created_at']?.toString() ?? now;
    final updatedAt = task['updated_at']?.toString() ?? now;
    final db = await database;
    final values = <String, Object?>{
      'id': id,
      'conversation_id': task['conversation_id']?.toString() ?? 'global',
      'status': task['status']?.toString() ?? 'pending',
      'payload_json': jsonEncode(task),
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
    await db.transaction((txn) async {
      final changed = await txn.update(
        'agent_tasks',
        values,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (changed == 0) await txn.insert('agent_tasks', values);
    });
  }

  /// Persists a child-agent projection and its immutable lifecycle event.
  /// Child prompts and dependency IDs are retained for explicit, reviewed recovery;
  /// this method never starts or replays work.
  Future<void> recordSubagentEvent(Map<String, dynamic> event) async {
    final taskId = event['task_id']?.toString() ?? '';
    final requestId = event['request_id']?.toString() ?? '';
    if (taskId.isEmpty || requestId.isEmpty) return;
    final db = await database;
    final rows = await db.query(
      'agent_tasks',
      where: 'id = ?',
      whereArgs: [taskId],
      limit: 1,
    );
    Map<String, dynamic> previous = <String, dynamic>{};
    if (rows.isNotEmpty) {
      final decoded = jsonDecode(rows.single['payload_json']! as String);
      if (decoded is Map) previous = Map<String, dynamic>.from(decoded);
      if (previous['kind'] != null && previous['kind'] != 'subagent') {
        throw StateError('Task id collision while persisting subagent $taskId.');
      }
    }
    final timestamp = event['timestamp']?.toString() ??
        DateTime.now().toUtc().toIso8601String();
    final now = DateTime.now().toUtc().toIso8601String();
    final snapshot = <String, dynamic>{
      ...previous,
      'id': taskId,
      'kind': 'subagent',
      'parent_request_id': requestId,
      'conversation_id': event['session_id']?.toString() ?? 'global',
      'agent_type': event['agent_type']?.toString() ?? 'unknown',
      'title': event['title']?.toString() ?? taskId,
      'prompt': event['task_prompt']?.toString() ?? previous['prompt'],
      'depends_on': event['depends_on'] ?? previous['depends_on'] ?? const <String>[],
      'status': event['status']?.toString() ?? 'pending',
      'last_event_type': event['type']?.toString() ?? 'unknown',
      'last_details': event['details']?.toString(),
      'created_at': previous['created_at']?.toString() ?? timestamp,
      'updated_at': now,
    };
    final payload = Map<String, Object?>.from(event);
    await saveTaskWithEvents(snapshot, events: <Map<String, Object?>>[
      <String, Object?>{
        'type': event['type']?.toString() ?? 'subagent_event',
        'status': event['status']?.toString() ?? 'pending',
        'payload': payload,
      },
    ]);
  }

  /// Marks children interrupted after process death. Side effects are never replayed.
  Future<int> reconcileInterruptedSubagents() async {
    final snapshots = (await getTasks())
        .where((task) => task['kind'] == 'subagent' &&
            {'pending', 'running'}.contains(task['status']))
        .toList(growable: false);
    for (final task in snapshots) {
      final now = DateTime.now().toUtc().toIso8601String();
      final recovered = <String, dynamic>{
        ...task,
        'status': 'interrupted',
        'last_event_type': 'subagent_interrupted_on_restart',
        'updated_at': now,
        'recovery_requires_explicit_resume': true,
      };
      await saveTaskWithEvents(recovered, events: <Map<String, Object?>>[
        <String, Object?>{
          'type': 'subagent_interrupted_on_restart',
          'status': 'interrupted',
          'payload': <String, Object?>{
            'parent_request_id': task['parent_request_id'],
            'replay': false,
            'requires_explicit_resume': true,
          },
        },
      ]);
    }
    return snapshots.length;
  }

  Future<List<Map<String, dynamic>>> subagentsForRequest(String requestId) async =>
      (await getTasks())
          .where((task) => task['kind'] == 'subagent' &&
              task['parent_request_id'] == requestId)
          .toList(growable: false);

  /// One-time compatibility migration. SharedPreferences is read only here;
  /// all subsequent task reads and writes use SQLite exclusively.
  Future<void> migrateLegacyTaskSnapshot() async {
    const legacyKey = 'giant_agent.tasks.v1';
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(legacyKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final tasks = decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
      await importLegacyTasksIfEmpty(tasks);
      final persisted = await getTasks();
      if (persisted.isNotEmpty || tasks.isEmpty) {
        await preferences.remove(legacyKey);
      }
    } on FormatException {
      // Preserve malformed legacy data for manual recovery; never discard it.
    }
  }

  Future<void> importLegacyTasksIfEmpty(
    List<Map<String, dynamic>> tasks,
  ) async {
    if (tasks.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      final count = Sqflite.firstIntValue(
            await txn.rawQuery('SELECT COUNT(*) FROM agent_tasks'),
          ) ??
          0;
      if (count != 0) return;
      for (final task in tasks) {
        final id = task['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final now = DateTime.now().toUtc().toIso8601String();
        await txn.insert('agent_tasks', {
          'id': id,
          'conversation_id': task['conversation_id']?.toString() ?? 'global',
          'status': task['status']?.toString() ?? 'pending',
          'payload_json': jsonEncode(task),
          'created_at': task['created_at']?.toString() ?? now,
          'updated_at': task['updated_at']?.toString() ?? now,
        });
      }
    });
  }

  /// Atomically updates the task projection and appends lifecycle events.
  /// Event rows are immutable; task snapshots are only a query-friendly projection.
  Future<void> saveTaskWithEvents(
    Map<String, dynamic> task, {
    required List<Map<String, Object?>> events,
  }) async {
    final id = task['id']?.toString() ?? '';
    if (id.isEmpty) throw ArgumentError.value(task, 'task', 'Task id is required.');
    final now = DateTime.now().toUtc().toIso8601String();
    final values = <String, Object?>{
      'id': id,
      'conversation_id': task['conversation_id']?.toString() ?? 'global',
      'status': task['status']?.toString() ?? 'pending',
      'payload_json': jsonEncode(task),
      'created_at': task['created_at']?.toString() ?? now,
      'updated_at': task['updated_at']?.toString() ?? now,
    };
    final db = await database;
    await db.transaction((txn) async {
      final changed = await txn.update(
        'agent_tasks',
        values,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (changed == 0) await txn.insert('agent_tasks', values);
      for (final event in events) {
        await _appendTaskEvent(
          txn,
          id,
          event['type']! as String,
          event['status']! as String,
          (event['payload'] as Map?)?.cast<String, Object?>() ?? const {},
          now,
        );
      }
    });
  }

  Future<List<KernelEventRecord>> taskEvents(String taskId) async {
    final rows = await (await database).query(
      'agent_events',
      where: 'task_id = ?',
      whereArgs: [taskId],
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

  Future<void> appendTaskEvent(
    String taskId,
    String type,
    String status, {
    Map<String, Object?> payload = const {},
  }) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final task = await txn.query(
        'agent_tasks',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [taskId],
        limit: 1,
      );
      if (task.isEmpty) throw StateError('Cannot journal an unknown task: $taskId');
      await _appendTaskEvent(txn, taskId, type, status, payload, now);
    });
  }

  Future<void> clearTasks() async =>
      (await database).delete('agent_tasks');

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

  Future<void> interrupt(String id, String result) =>
      _finish(id, 'interrupted', result: result);

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
        status == 'completed'
            ? 'request_completed'
            : status == 'interrupted'
                ? 'request_interrupted'
                : 'request_failed',
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

  /// Appends a factual runtime/timeline event to its parent request journal.
  /// Events are immutable and duplicate IDs are ignored during stream retries.
  Future<void> appendRequestEvent(Map<String, dynamic> event) async {
    final requestId = event['request_id']?.toString() ?? '';
    if (requestId.isEmpty || requestId == 'runtime') return;
    final id = event['id']?.toString() ?? '';
    final type = event['type']?.toString() ?? 'unknown';
    if (id.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final createdAt = event['timestamp']?.toString() ?? now;
    final db = await database;
    await db.transaction((txn) async {
      final request = await txn.query(
        'agent_requests',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [requestId],
        limit: 1,
      );
      if (request.isEmpty) return;
      final values = <String, Object?>{
        'id': id,
        'request_id': requestId,
        'type': type,
        'status': event['status']?.toString() ?? 'pending',
        'payload_json': jsonEncode(event),
        'created_at': createdAt,
      };
      final taskId = event['task_id']?.toString();
      if (taskId != null && taskId.isNotEmpty) {
        final columns = await txn.rawQuery('PRAGMA table_info(agent_events)');
        if (columns.any((column) => column['name'] == 'task_id')) {
          values['task_id'] = taskId;
        }
      }
      await txn.insert(
        'agent_events',
        values,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    });
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

  Future<void> _appendTaskEvent(
    Transaction txn,
    String taskId,
    String type,
    String status,
    Map<String, Object?> payload,
    String timestamp,
  ) async {
    await txn.insert('agent_events', {
      'id': '${taskId}_${type}_${DateTime.now().microsecondsSinceEpoch}',
      'request_id': null,
      'task_id': taskId,
      'type': type,
      'status': status,
      'payload_json': jsonEncode(payload),
      'created_at': timestamp,
    });
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
