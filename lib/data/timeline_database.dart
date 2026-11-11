import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/timeline_engine.dart';

class TimelineSession {
  const TimelineSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory TimelineSession.fromMap(Map<String, Object?> map) => TimelineSession(
    id: map['id'].toString(),
    title: map['title']?.toString() ?? 'Untitled session',
    createdAt: DateTime.fromMillisecondsSinceEpoch(_toInt(map['created_at'])),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(_toInt(map['updated_at'])),
  );
}

int _toInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;

class TimelineDatabase {
  TimelineDatabase._();
  static final TimelineDatabase instance = TimelineDatabase._();

  Database? _database;
  Future<Database>? _opening;

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    return _opening ??= _open().whenComplete(() => _opening = null);
  }

  Future<Database> _open() async {
    final root = await getDatabasesPath();
    final db = await openDatabase(
      p.join(root, 'giant_agent_timeline.db'),
      version: 2,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _createSchema,
      onUpgrade: _upgrade,
    );
    _database = db;
    return db;
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE timeline_sessions (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE timeline_events (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        type TEXT NOT NULL,
        title TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        description TEXT,
        agent_id TEXT,
        parent_agent_id TEXT,
        tool_call_id TEXT,
        tool_name TEXT,
        progress REAL,
        error TEXT,
        metadata_json TEXT NOT NULL DEFAULT '{}',
        completed_at INTEGER,
        FOREIGN KEY(session_id) REFERENCES timeline_sessions(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX timeline_events_session_time ON timeline_events(session_id, created_at, id)');
    await db.execute('CREATE INDEX timeline_events_tool_call ON timeline_events(session_id, tool_call_id)');
  }

  Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('CREATE INDEX IF NOT EXISTS timeline_events_tool_call ON timeline_events(session_id, tool_call_id)');
    }
  }

  Future<TimelineSession> createSession({String title = 'New session'}) async {
    final db = await database;
    final now = DateTime.now();
    final session = TimelineSession(
      id: timelineNewId('session'), title: title,
      createdAt: now, updatedAt: now,
    );
    await db.insert('timeline_sessions', {
      'id': session.id, 'title': session.title,
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
    });
    return session;
  }

  Future<void> updateSession(String sessionId, {String? title}) async {
    final db = await database;
    await db.update('timeline_sessions', {
      if (title != null) 'title': title,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, where: 'id = ?', whereArgs: [sessionId]);
  }

  Future<List<TimelineSession>> getSessions({int limit = 100}) async {
    final rows = await (await database).query(
      'timeline_sessions', orderBy: 'updated_at DESC', limit: limit,
    );
    return rows.map(TimelineSession.fromMap).toList(growable: false);
  }

  Future<TimelineSession?> getSession(String sessionId) async {
    final rows = await (await database).query(
      'timeline_sessions', where: 'id = ?', whereArgs: [sessionId], limit: 1,
    );
    return rows.isEmpty ? null : TimelineSession.fromMap(rows.first);
  }

  Future<void> saveEvent(AgentTimelineEvent event) async {
    final db = await database;
    await db.transaction((txn) async {
      final session = await txn.query(
        'timeline_sessions', columns: ['id'],
        where: 'id = ?', whereArgs: [event.sessionId], limit: 1,
      );
      if (session.isEmpty) {
        throw StateError('Timeline session ${event.sessionId} does not exist');
      }
      await txn.insert(
        'timeline_events', event.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.update('timeline_sessions', {
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }, where: 'id = ?', whereArgs: [event.sessionId]);
    });
  }

  Future<List<AgentTimelineEvent>> loadEvents(
    String sessionId, {
    int limit = 500,
    int offset = 0,
  }) async {
    final rows = await (await database).query(
      'timeline_events',
      where: 'session_id = ?', whereArgs: [sessionId],
      orderBy: 'created_at ASC, id ASC', limit: limit, offset: offset,
    );
    return rows.map(AgentTimelineEvent.fromMap).toList(growable: false);
  }

  Future<int> deleteSession(String sessionId) async {
    final db = await database;
    return db.transaction((txn) async {
      await txn.delete('timeline_events', where: 'session_id = ?', whereArgs: [sessionId]);
      return txn.delete('timeline_sessions', where: 'id = ?', whereArgs: [sessionId]);
    });
  }

  Future<int> deleteEvents(String sessionId) async =>
      (await database).delete('timeline_events',
        where: 'session_id = ?', whereArgs: [sessionId]);

  Future<void> close() async {
    final db = _database;
    _database = null;
    if (db != null && db.isOpen) await db.close();
  }
}
