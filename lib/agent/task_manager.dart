import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/agent_service.dart';

/// Persistent task lifecycle backed by the real local agent runtime.
/// Task history survives process restarts; completion is recorded only after
/// the agent returns its final result.
class TaskManager {
  TaskManager._internal();
  static final TaskManager _instance = TaskManager._internal();
  factory TaskManager() => _instance;

  static const String _storageKey = 'giant_agent.tasks.v1';
  final AgentService _agent = AgentService.instance;
  final List<Map<String, dynamic>> _tasks = [];
  String _currentTask = '';
  bool _executing = false;
  Future<void>? _loading;
  Future<void> _writeTail = Future<void>.value();

  Future<void> _ensureLoaded() {
    _loading ??= _load();
    return _loading!;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _tasks
        ..clear()
        ..addAll(decoded.whereType<Map>().map((item) {
          final task = Map<String, dynamic>.from(item);
          // A process may die while a task is running. Never report it as
          // actively executing after restart; it is explicitly resumable.
          if (task['status'] == 'running') {
            task['status'] = 'paused';
            task['recovery_note'] = 'توقف التطبيق أثناء التنفيذ؛ يمكن استئناف المهمة.';
            final steps = task['steps'];
            if (steps is List) {
              for (final rawStep in steps) {
                if (rawStep is Map && rawStep['status'] == 'running') {
                  rawStep['status'] = 'pending';
                }
              }
            }
          }
          return task;
        }));
      if (_tasks.isNotEmpty) {
        _currentTask = _tasks.last['id']?.toString() ?? '';
      }
      await _persist();
    } on FormatException {
      // Keep a corrupt preference untouched for diagnosis; start with an
      // empty in-memory queue rather than crashing the agent UI.
    }
  }

  Future<void> _persist() {
    final snapshot = jsonEncode(_tasks);
    final completer = Completer<void>();
    final previous = _writeTail;
    _writeTail = completer.future;
    return () async {
      await previous;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_storageKey, snapshot);
        completer.complete();
      } catch (error, stack) {
        completer.completeError(error, stack);
        rethrow;
      }
    }();
  }

  Map<String, dynamic> _copyTask(Map<String, dynamic> task) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(task)) as Map);

  Future<Map<String, dynamic>> createTask(String description) async {
    await _ensureLoaded();
    final goal = description.trim();
    if (goal.isEmpty) throw ArgumentError.value(description, 'description');
    final now = DateTime.now();
    final id = now.microsecondsSinceEpoch.toString();
    final task = <String, dynamic>{
      'id': id,
      'description': goal,
      'status': 'pending',
      'steps': <Map<String, dynamic>>[
        {
          'step': 1,
          'action': 'تنفيذ المهمة بواسطة محرك الوكيل المحلي',
          'type': 'agent_execution',
          'status': 'pending',
        }
      ],
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };
    _tasks.add(task);
    _currentTask = id;
    await _persist();
    return _copyTask(task);
  }

  Future<bool> selectTask(String taskId) async {
    await _ensureLoaded();
    final exists = _tasks.any((item) => item['id'] == taskId);
    if (!exists || _executing) return false;
    _currentTask = taskId;
    await _persist();
    return true;
  }

  Future<Map<String, dynamic>> resumeTask(String taskId) async {
    await _ensureLoaded();
    if (_executing) throw StateError('يوجد تنفيذ مهمة جارٍ بالفعل.');
    final task = _tasks.cast<Map<String, dynamic>>().firstWhere(
      (item) => item['id'] == taskId,
      orElse: () => <String, dynamic>{},
    );
    if (task.isEmpty) return {'status': 'missing', 'message': 'المهمة غير موجودة.'};
    if (task['status'] == 'completed') {
      return {'status': 'completed', 'task_summary': _copyTask(task)};
    }
    if (task['status'] != 'paused' && task['status'] != 'failed' && task['status'] != 'pending') {
      return {'status': task['status'], 'task_summary': _copyTask(task)};
    }
    _currentTask = taskId;
    task['status'] = 'pending';
    task.remove('error');
    task.remove('recovery_note');
    task['updated_at'] = DateTime.now().toIso8601String();
    await _persist();
    return executeNextStep();
  }

  Future<Map<String, dynamic>> executeNextStep() async {
    await _ensureLoaded();
    if (_executing) throw StateError('يوجد تنفيذ مهمة جارٍ بالفعل.');
    final task = _tasks.cast<Map<String, dynamic>>().firstWhere(
      (item) => item['id'] == _currentTask,
      orElse: () => <String, dynamic>{},
    );
    if (task.isEmpty) return {'status': 'missing', 'message': 'لا توجد مهمة نشطة.'};
    if (task['status'] == 'completed') {
      return {'status': 'completed', 'task_summary': _copyTask(task)};
    }

    _executing = true;
    final step = (task['steps'] as List).first as Map<String, dynamic>;
    task['status'] = 'running';
    task['started_at'] ??= DateTime.now().toIso8601String();
    task['updated_at'] = DateTime.now().toIso8601String();
    step['status'] = 'running';
    await _persist();
    try {
      final result = await _agent.runTask(task['description'] as String);
      step['status'] = 'completed';
      step['result'] = result;
      task['status'] = 'completed';
      task['completed_at'] = DateTime.now().toIso8601String();
      task['updated_at'] = task['completed_at'];
      task['result'] = result;
      await _persist();
      return {
        'status': 'completed',
        'step': step['step'],
        'action': step['action'],
        'result': result,
        'remaining': 0,
        'task_summary': _copyTask(task),
      };
    } catch (error) {
      step['status'] = 'failed';
      step['error'] = error.toString();
      task['status'] = 'failed';
      task['error'] = error.toString();
      task['updated_at'] = DateTime.now().toIso8601String();
      await _persist();
      return {'status': 'failed', 'error': error.toString(), 'task_summary': _copyTask(task)};
    } finally {
      _executing = false;
    }
  }

  Future<bool> cancelTask() async {
    if (!_executing) return false;
    final accepted = await _agent.cancel();
    if (accepted) {
      final task = _tasks.cast<Map<String, dynamic>>().firstWhere(
        (item) => item['id'] == _currentTask,
        orElse: () => <String, dynamic>{},
      );
      if (task.isNotEmpty) {
        task['cancel_requested_at'] = DateTime.now().toIso8601String();
        task['updated_at'] = task['cancel_requested_at'];
        await _persist();
      }
    }
    return accepted;
  }

  String getProgress() {
    final task = _tasks.cast<Map<String, dynamic>>().firstWhere(
      (item) => item['id'] == _currentTask,
      orElse: () => <String, dynamic>{},
    );
    if (task.isEmpty) return 'لا توجد مهمة نشطة';
    final status = task['status'];
    return status == 'completed'
        ? 'مكتمل'
        : status == 'failed'
            ? 'فشل'
            : status == 'paused'
                ? 'متوقف مؤقتاً — قابل للاستئناف'
                : status == 'running'
                    ? 'قيد التنفيذ'
                    : 'بانتظار التنفيذ';
  }

  List<Map<String, dynamic>> getTasks() =>
      _tasks.map(_copyTask).toList(growable: false);

  Future<void> clearTasks() async {
    await _ensureLoaded();
    if (_executing) throw StateError('لا يمكن مسح المهام أثناء التنفيذ.');
    _tasks.clear();
    _currentTask = '';
    await _persist();
  }
}
