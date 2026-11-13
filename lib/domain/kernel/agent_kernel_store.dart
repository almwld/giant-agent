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
  /// Process-wide production store shared by AgentService and ModelService.
  /// Tests may still inject isolated stores through the regular constructor.
  static final AgentKernelStore shared = AgentKernelStore();

  AgentKernelStore({KernelDatabaseProvider? databaseProvider})
      : _databaseProvider = databaseProvider ?? _openDefaultDatabase;

  final KernelDatabaseProvider _databaseProvider;
  Database? _database;

  static Future<Database> _openDefaultDatabase() async {
    final directory = await getApplicationSupportDirectory();
    await Directory(directory.path).create(recursive: true);
    return openDatabase(
      '${directory.path}/giant_agent_kernel.db',
      version: 5,
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
        await _createOutputTable(db);
        await _createSubagentRuntimeStateTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createTaskTable(db);
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE agent_events ADD COLUMN task_id TEXT');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_agent_events_task ON agent_events(task_id, row_id)');
        }
        if (oldVersion < 4) await _createOutputTable(db);
        if (oldVersion < 5) await _createSubagentRuntimeStateTable(db);
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

  static Future<void> _createOutputTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS agent_outputs (
        id TEXT PRIMARY KEY,
        request_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        task_id TEXT,
        kind TEXT NOT NULL,
        title TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        file_path TEXT,
        content TEXT,
        preview TEXT,
        status TEXT NOT NULL,
        verified INTEGER NOT NULL DEFAULT 0,
        verification_message TEXT,
        metadata_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_agent_outputs_request
      ON agent_outputs(request_id, created_at)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_agent_outputs_conversation
      ON agent_outputs(conversation_id, created_at)
    ''');
  }

  /// Stores a durable output artifact projection, separate from the immutable event journal.
  Future<void> saveOutputArtifact(Map<String, dynamic> artifact) async {
    final id = artifact['id']?.toString() ?? '';
    final requestId = artifact['request_id']?.toString() ?? '';
    if (id.isEmpty || requestId.isEmpty) {
      throw ArgumentError('Output artifact id and request id are required.');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final metadata = artifact['metadata'] is Map
        ? Map<String, Object?>.from(artifact['metadata'] as Map)
        : <String, Object?>{};
    await (await database).insert('agent_outputs', <String, Object?>{
      'id': id,
      'request_id': requestId,
      'conversation_id': artifact['conversation_id']?.toString() ?? 'global',
      'task_id': artifact['task_id']?.toString(),
      'kind': artifact['kind']?.toString() ?? 'text',
      'title': artifact['title']?.toString() ?? 'مخرج الوكيل',
      'mime_type': artifact['mime_type']?.toString() ?? 'text/plain',
      'file_path': artifact['file_path']?.toString(),
      'content': artifact['content']?.toString(),
      'preview': artifact['preview']?.toString(),
      'status': artifact['status']?.toString() ?? 'available',
      'verified': artifact['verified'] == true ? 1 : 0,
      'verification_message': artifact['verification_message']?.toString(),
      'metadata_json': jsonEncode(metadata),
      'created_at': artifact['created_at']?.toString() ?? now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> outputsForRequest(String requestId) async {
    final rows = await (await database).query(
      'agent_outputs', where: 'request_id = ?', whereArgs: [requestId],
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map((row) => <String, dynamic>{
      ...row,
      'verified': (row['verified'] as num?)?.toInt() == 1,
      'metadata': jsonDecode(row['metadata_json']! as String),
    }).toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> outputsForConversation(String conversationId) async {
    final rows = await (await database).query(
      'agent_outputs', where: 'conversation_id = ?', whereArgs: [conversationId],
      orderBy: 'created_at DESC, id ASC',
    );
    return rows.map((row) => <String, dynamic>{
      ...row,
      'verified': (row['verified'] as num?)?.toInt() == 1,
      'metadata': jsonDecode(row['metadata_json']! as String),
    }).toList(growable: false);
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

  static Future<void> _createSubagentRuntimeStateTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS agent_subagent_runtime_state (
        request_id TEXT PRIMARY KEY,
        payload_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  /// Persists request-scoped goal and mailbox state independently from the
  /// append-only lifecycle journal. A mailbox write is an atomic replacement.
  Future<void> saveSubagentRuntimeState(
    String requestId,
    Map<String, Object?> state,
  ) async {
    if (requestId.trim().isEmpty) {
      throw ArgumentError.value(requestId, 'requestId', 'Request id is required.');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final payload = jsonEncode(state);
    await (await database).insert(
      'agent_subagent_runtime_state',
      <String, Object?>{
        'request_id': requestId,
        'payload_json': payload,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, Object?>?> loadSubagentRuntimeState(String requestId) async {
    if (requestId.trim().isEmpty) return null;
    final rows = await (await database).query(
      'agent_subagent_runtime_state',
      where: 'request_id = ?',
      whereArgs: [requestId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      final decoded = jsonDecode(rows.single['payload_json']! as String);
      if (decoded is! Map) return null;
      return Map<String, Object?>.from(decoded);
    } on FormatException {
      // Preserve the corrupt row for diagnosis; do not silently overwrite it.
      return null;
    }
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
    final eventType = event['type']?.toString() ?? 'unknown';
    final eventStatus = eventType == 'subagent_cancelled'
        ? 'cancelled'
        : event['status']?.toString() ?? 'pending';
    final snapshot = <String, dynamic>{
      ...previous,
      'id': taskId,
      'kind': 'subagent',
      'parent_request_id': requestId,
      'conversation_id': event['session_id']?.toString() ?? 'global',
      'agent_type': event['agent_type']?.toString() ?? 'unknown',
      'subagent_id': event['subagent_id']?.toString() ?? previous['subagent_id'],
      'is_async': event['is_async'] == true || previous['is_async'] == true,
      'title': event['title']?.toString() ?? taskId,
      'icon': event['icon']?.toString() ?? previous['icon'] ?? 'smart_toy',
      'motto': event['motto']?.toString() ?? previous['motto'] ?? '',
      'index': event['index'] is int ? event['index'] as int : previous['index'] ?? 0,
      'prompt': event['task_prompt']?.toString() ?? previous['prompt'],
      'depends_on': event['depends_on'] ?? previous['depends_on'] ?? const <String>[],
      'status': eventStatus,
      'last_event_type': eventType,
      'last_details': event['details']?.toString(),
      'last_result': event['result']?.toString() ?? previous['last_result'],
      'is_dismissed': eventType == 'subagent_dismissed'
          ? true
          : previous['is_dismissed'] == true,
      'dismissed_at': eventType == 'subagent_dismissed'
          ? timestamp
          : previous['dismissed_at'],
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
    var recoveredCount = 0;
    final db = await database;

    // The request-scoped runtime snapshot is written before lifecycle events
    // are published. Reconcile it first so a crash between the state write and
    // event projection cannot leave a started child looking safely pending.
    final runtimeRows = await db.query('agent_subagent_runtime_state');
    for (final row in runtimeRows) {
      final requestId = row['request_id']?.toString() ?? '';
      if (requestId.isEmpty) continue;
      late Map<String, Object?> state;
      try {
        final decoded = jsonDecode(row['payload_json']! as String);
        if (decoded is! Map || decoded['records'] is! Map) continue;
        state = Map<String, Object?>.from(decoded);
      } on FormatException {
        // Preserve malformed durable state for diagnosis.
        continue;
      }
      final rawRecords = state['records'];
      if (rawRecords is! Map) continue;
      final records = Map<String, Object?>.from(rawRecords);
      var stateChanged = false;
      for (final entry in records.entries.toList()) {
        if (entry.value is! Map) continue;
        final record = Map<String, dynamic>.from(entry.value as Map);
        final status = record['status']?.toString() ?? '';
        final needsRecovery = status == 'running' ||
            (status == 'pending' && record['is_async'] != true);
        if (!needsRecovery) continue;

        final now = DateTime.now().toUtc().toIso8601String();
        record
          ..['status'] = 'interrupted'
          ..['wire_status'] = 'STATUS_TERMINATED'
          ..['error'] = 'Process restarted before this child reached a terminal state.'
          ..['updated_at'] = now;
        records[entry.key] = record;
        stateChanged = true;

        final taskId = record['task_id']?.toString() ?? '';
        if (taskId.isEmpty) continue;
        final dependencies = (record['depends_on'] as List? ?? const <dynamic>[])
            .map((value) => '${requestId}_dynamic_${value.toString()}')
            .toList(growable: false);
        final snapshot = <String, dynamic>{
          'id': taskId,
          'kind': 'subagent',
          'parent_request_id': requestId,
          'subagent_id': record['id']?.toString() ?? entry.key.toString(),
          'conversation_id': record['conversation_id']?.toString() ?? 'global',
          'agent_type': record['agent_type']?.toString() ?? 'unknown',
          'title': record['title']?.toString() ?? taskId,
          'icon': record['icon']?.toString() ?? 'smart_toy',
          'motto': record['motto']?.toString() ?? '',
          'index': record['index'] ?? 0,
          'is_async': record['is_async'] == true,
          'prompt': record['prompt']?.toString() ?? '',
          'depends_on': dependencies,
          'status': 'interrupted',
          'last_event_type': 'subagent_interrupted_on_restart',
          'last_details': 'Process restarted while child execution was active or not yet safely admitted.',
          'last_result': record['result'],
          'is_dismissed': record['dismissed'] == true,
          'created_at': record['created_at']?.toString() ?? now,
          'updated_at': now,
          'recovery_requires_explicit_resume': true,
        };
        await saveTaskWithEvents(snapshot, events: <Map<String, Object?>>[
          <String, Object?>{
            'type': 'subagent_interrupted_on_restart',
            'status': 'interrupted',
            'payload': <String, Object?>{
              'request_id': requestId,
              'subagent_id': snapshot['subagent_id'],
              'is_async': snapshot['is_async'],
              'replay': false,
              'requires_explicit_resume': true,
            },
          },
        ]);
        recoveredCount++;
      }
      if (stateChanged) {
        state['records'] = records;
        state['updated_at'] = DateTime.now().toUtc().toIso8601String();
        await db.update(
          'agent_subagent_runtime_state',
          <String, Object?>{
            'payload_json': jsonEncode(state),
            'updated_at': state['updated_at'],
          },
          where: 'request_id = ?',
          whereArgs: [requestId],
        );
      }
    }

    // Reconcile legacy/static child projections that do not have a matching
    // request-scoped dynamic record.
    final snapshots = (await getTasks())
        .where((task) => task['kind'] == 'subagent' &&
            (task['status'] == 'running' ||
                (task['status'] == 'pending' && task['is_async'] != true)))
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
      recoveredCount++;
    }
    return recoveredCount;
  }

  Future<List<Map<String, dynamic>>> subagentsForRequest(String requestId) async =>
      (await getTasks())
          .where((task) => task['kind'] == 'subagent' &&
              task['parent_request_id'] == requestId)
          .toList(growable: false);

  /// Returns detached children admitted but not yet started. These are safe to
  /// re-enqueue after process restart because no execution side effect began.
  Future<List<Map<String, dynamic>>> pendingAsyncSubagents() async {
    // The request-scoped lifecycle snapshot is written before the enqueue
    // event is published. Read it as the admission source so a process death
    // in the small event-projection window cannot lose a queued child.
    final rows = await (await database).query('agent_subagent_runtime_state');
    final pending = <Map<String, dynamic>>[];
    for (final row in rows) {
      final requestId = row['request_id']?.toString() ?? '';
      if (requestId.isEmpty) continue;
      try {
        final decoded = jsonDecode(row['payload_json']! as String);
        if (decoded is! Map || decoded['records'] is! Map) continue;
        final records = decoded['records'] as Map;
        for (final value in records.values) {
          if (value is! Map) continue;
          final record = Map<String, dynamic>.from(value);
          if (record['status'] != 'pending' || record['is_async'] != true ||
              record['dismissed'] == true) continue;
          pending.add(<String, dynamic>{
            ...record,
            'subagent_id': record['id']?.toString() ?? '',
            'task_id': record['task_id']?.toString() ?? '',
            'parent_request_id': requestId,
            'kind': 'subagent',
          });
        }
      } on FormatException {
        // Keep corrupt durable state intact for diagnosis; never invent a task.
      }
    }
    return pending;
  }

  /// Returns durable child snapshots grouped by the chat/conversation that owns them.
  Future<List<Map<String, dynamic>>> subagentsForConversation(String conversationId) async =>
      (await getTasks())
          .where((task) => task['kind'] == 'subagent' &&
              task['conversation_id'] == conversationId)
          .toList(growable: false);

  /// Loads one durable child-agent projection by stable task id.
  Future<Map<String, dynamic>?> getSubagent(String taskId) async {
    final rows = await (await database).query('agent_tasks',
      where: 'id = ?', whereArgs: [taskId], limit: 1);
    if (rows.isEmpty) return null;
    final decoded = jsonDecode(rows.single['payload_json']! as String);
    if (decoded is! Map || decoded['kind'] != 'subagent') return null;
    return Map<String, dynamic>.from(decoded);
  }

  /// Soft-deletes a terminal child from active management while retaining
  /// its immutable event journal and original terminal status for audit.
  Future<bool> dismissSubagent(String taskId) async {
    final task = await getSubagent(taskId);
    if (task == null) return false;
    if (task['is_dismissed'] == true) return true;
    final status = task['status']?.toString() ?? 'unknown';
    if (status == 'pending' || status == 'running') return false;
    final requestId = task['parent_request_id']?.toString() ?? '';
    if (requestId.isEmpty) return false;
    await recordSubagentEvent(<String, dynamic>{
      'id': 'subagent_dismissed_${taskId}_${DateTime.now().microsecondsSinceEpoch}',
      'request_id': requestId,
      'session_id': task['conversation_id']?.toString() ?? 'global',
      'task_id': taskId,
      'agent_type': task['agent_type']?.toString() ?? 'unknown',
      'title': task['title']?.toString() ?? taskId,
      'task_prompt': task['prompt']?.toString() ?? '',
      'depends_on': task['depends_on'] ?? const <String>[],
      'type': 'subagent_dismissed',
      'status': status,
      'details': 'Dismissed from active management; audit history retained.',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });
    return true;
  }

  /// Atomically claims an interrupted child for a user-authorized resume.
  /// The caller must explicitly classify the possible prior side effects.
  /// Dependency outputs are reconstructed from durable completed snapshots.
  Future<Map<String, dynamic>> claimSubagentResume(
    String taskId, {
    required String sideEffectDisposition,
  }) async {
    const allowed = {'verified_no_side_effects', 'user_authorized_retry'};
    if (!allowed.contains(sideEffectDisposition)) {
      throw ArgumentError.value(sideEffectDisposition, 'sideEffectDisposition',
        'An explicit side-effect disposition is required.');
    }
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    late Map<String, dynamic> claimed;
    await db.transaction((txn) async {
      final rows = await txn.query('agent_tasks', where: 'id = ?',
        whereArgs: [taskId], limit: 1);
      if (rows.isEmpty) throw StateError('الوكيل الفرعي غير موجود.');
      final decoded = jsonDecode(rows.single['payload_json']! as String);
      if (decoded is! Map || decoded['kind'] != 'subagent') {
        throw StateError('السجل المحدد ليس وكيلاً فرعياً.');
      }
      final task = Map<String, dynamic>.from(decoded);
      final status = task['status']?.toString();
      if (task['is_dismissed'] == true) {
        throw StateError('تم إخفاء الوكيل من الإدارة ولا يمكن استئنافه.');
      }
      if (status == 'completed' || status == 'cancelled') {
        throw StateError('لا يمكن استئناف وكيل مكتمل أو ملغى.');
      }
      if (status != 'interrupted' && status != 'failed') {
        throw StateError('الوكيل الفرعي ليس في حالة تسمح بالاستئناف: $status');
      }
      if ((task['prompt']?.toString() ?? '').trim().isEmpty) {
        throw StateError('تعذر استعادة تعليمات الوكيل الفرعي الأصلية.');
      }
      final dependencies = (task['depends_on'] as List? ?? const [])
          .map((value) => value.toString()).toList(growable: false);
      final dependencyResults = <String, String>{};
      for (final dependencyId in dependencies) {
        final dependencyRows = await txn.query('agent_tasks',
          where: 'id = ?', whereArgs: [dependencyId], limit: 1);
        if (dependencyRows.isEmpty) {
          throw StateError('تعذر إعادة بناء التبعية $dependencyId.');
        }
        final dependencyDecoded = jsonDecode(
          dependencyRows.single['payload_json']! as String);
        if (dependencyDecoded is! Map ||
            dependencyDecoded['kind'] != 'subagent' ||
            dependencyDecoded['parent_request_id'] != task['parent_request_id'] ||
            dependencyDecoded['status'] != 'completed') {
          throw StateError('التبعية $dependencyId ليست مكتملة ضمن المهمة الأصلية.');
        }
        final output = dependencyDecoded['last_result']?.toString() ?? '';
        if (output.isEmpty) {
          throw StateError('نتيجة التبعية $dependencyId غير محفوظة بالكامل.');
        }
        dependencyResults[dependencyId] = output;
      }
      final attempts = (task['resume_attempts'] as num?)?.toInt() ?? 0;
      task['status'] = 'running';
      task['resume_attempts'] = attempts + 1;
      task['resume_authorized_at'] = now;
      task['side_effect_disposition'] = sideEffectDisposition;
      task['recovery_requires_explicit_resume'] = false;
      task['updated_at'] = now;
      task['dependency_results_snapshot'] = dependencyResults;
      final values = <String, Object?>{
        'id': taskId,
        'conversation_id': task['conversation_id']?.toString() ?? 'global',
        'status': 'running',
        'payload_json': jsonEncode(task),
        'created_at': task['created_at']?.toString() ?? now,
        'updated_at': now,
      };
      await txn.update('agent_tasks', values, where: 'id = ?', whereArgs: [taskId]);
      await _appendTaskEvent(txn, taskId, 'subagent_resume_authorized', 'running',
        <String, Object?>{
          'authorization': 'explicit_user_action',
          'side_effect_disposition': sideEffectDisposition,
          'resume_attempt': attempts + 1,
          'dependencies_reconstructed': dependencies,
          'automatic_replay': false,
        }, now);
      claimed = task;
    });
    return claimed;
  }

  /// Persists the terminal/interrupted state of a resumed child and full output.
  Future<void> finishSubagentResume(
    String taskId, {
    String? result,
    String? error,
    required String status,
  }) async {
    if (!{'completed', 'failed', 'interrupted'}.contains(status)) {
      throw ArgumentError.value(status, 'status');
    }
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final rows = await txn.query('agent_tasks', where: 'id = ?',
        whereArgs: [taskId], limit: 1);
      if (rows.isEmpty) throw StateError('الوكيل الفرعي غير موجود.');
      final decoded = jsonDecode(rows.single['payload_json']! as String);
      if (decoded is! Map || decoded['kind'] != 'subagent' || decoded['status'] != 'running') {
        throw StateError('لا توجد محاولة استئناف نشطة لهذا الوكيل.');
      }
      final task = Map<String, dynamic>.from(decoded)
        ..['status'] = status
        ..['updated_at'] = now
        ..['last_event_type'] = 'subagent_resume_$status';
      if (result != null) task['last_result'] = result;
      if (error != null) task['last_error'] = error;
      if (status == 'completed') {
        task['completed_at'] = now;
        task.remove('last_error');
        task['recovery_requires_explicit_resume'] = false;
      } else {
        task['recovery_requires_explicit_resume'] = true;
      }
      await txn.update('agent_tasks', <String, Object?>{
        'id': taskId,
        'conversation_id': task['conversation_id']?.toString() ?? 'global',
        'status': status,
        'payload_json': jsonEncode(task),
        'created_at': task['created_at']?.toString() ?? now,
        'updated_at': now,
      }, where: 'id = ?', whereArgs: [taskId]);
      await _appendTaskEvent(txn, taskId, 'subagent_resume_$status', status,
        <String, Object?>{
          if (result != null) 'result': result,
          if (error != null) 'error': error,
        }, now);
    });
  }

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

  Future<bool> hasActiveRequests() async {
    final count = Sqflite.firstIntValue(await (await database).rawQuery(
      "SELECT COUNT(*) FROM agent_requests WHERE status IN ('queued', 'running')",
    )) ?? 0;
    return count > 0;
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

  /// Completes a previously interrupted parent only after its recovered
  /// children have been re-synthesized and the Output Engine has verified all artifacts.
  Future<void> completeInterruptedRequest(String id, String result) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final changed = await txn.update(
        'agent_requests',
        <String, Object?>{
          'status': 'completed',
          'result': result,
          'error': null,
          'completed_at': now,
          'updated_at': now,
        },
        where: "id = ? AND status IN ('interrupted', 'failed')",
        whereArgs: [id],
      );
      if (changed != 1) throw StateError('Request $id is not recoverable from its current state.');
      await _appendEvent(
        txn,
        id,
        'request_recovered_completed',
        'completed',
        <String, Object?>{'recovered_after_child_resume': true, 'output_verified': true},
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
  /// Appends privacy-filtered analytics facts to the canonical event journal.
  /// System analytics have no request owner and therefore use a null request_id.
  Future<void> appendAnalyticsEvent({
    required String eventType,
    Map<String, Object?> data = const <String, Object?>{},
  }) async {
    final normalizedType = eventType.trim();
    if (normalizedType.isEmpty || normalizedType.length > 80) {
      throw ArgumentError.value(eventType, 'eventType', 'Invalid analytics event type.');
    }
    final id = 'analytics_${DateTime.now().microsecondsSinceEpoch}_${normalizedType.hashCode}';
    final now = DateTime.now().toUtc().toIso8601String();
    await (await database).insert('agent_events', <String, Object?>{
      'id': id,
      'request_id': null,
      'task_id': null,
      'type': 'analytics_$normalizedType',
      'status': 'recorded',
      'payload_json': jsonEncode(<String, Object?>{
        'type': 'analytics_$normalizedType',
        'status': 'recorded',
        'data': data,
      }),
      'created_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

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
