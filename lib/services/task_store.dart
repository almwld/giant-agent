import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/task_model.dart';

abstract interface class TaskStore {
  Future<void> initialize();
  Future<List<TaskModel>> loadAll();
  Future<void> save(TaskModel task);
  Future<void> clear();
}

class SqliteTaskStore implements TaskStore {
  static const String _databaseName = 'giant_agent_tasks.db';
  static const String _tableName = 'agent_tasks';
  Future<Database>? _databaseFuture;

  Future<Database> _database() {
    return _databaseFuture ??= _openDatabase();
  }

  Future<Database> _openDatabase() async {
    final root = await getDatabasesPath();
    return openDatabase(
      '$root/$_databaseName',
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            id TEXT PRIMARY KEY,
            status TEXT NOT NULL,
            payload TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX agent_tasks_updated_at ON $_tableName(updated_at)',
        );
      },
    );
  }

  @override
  Future<void> initialize() async {
    await _database();
  }

  @override
  Future<List<TaskModel>> loadAll() async {
    final rows = await (await _database()).query(
      _tableName,
      columns: const ['payload'],
      orderBy: 'updated_at DESC',
    );
    return rows.map((row) {
      final decoded = jsonDecode(row['payload']! as String);
      if (decoded is! Map) throw const FormatException('Invalid task payload in storage.');
      return TaskModel.fromJson(Map<String, dynamic>.from(decoded));
    }).toList();
  }

  @override
  Future<void> save(TaskModel task) async {
    await (await _database()).insert(
      _tableName,
      {
        'id': task.id,
        'status': task.status.name,
        'payload': jsonEncode(task.toJson()),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> clear() async {
    await (await _database()).delete(_tableName);
  }
}
