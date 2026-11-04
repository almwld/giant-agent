import 'dart:async';

import '../services/agent_service.dart';

/// Task lifecycle backed by the real local agent runtime. A task is never
/// marked complete until the model service returns a final response.
class TaskManager {
  TaskManager._internal();
  static final TaskManager _instance = TaskManager._internal();
  factory TaskManager() => _instance;

  final AgentService _agent = AgentService.instance;
  final List<Map<String, dynamic>> _tasks = [];
  String _currentTask = '';
  bool _executing = false;

  Future<Map<String, dynamic>> createTask(String description) async {
    final goal = description.trim();
    if (goal.isEmpty) throw ArgumentError.value(description, 'description');
    final id = DateTime.now().microsecondsSinceEpoch.toString();
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
      'created_at': DateTime.now().toIso8601String(),
    };
    _tasks.add(task);
    _currentTask = id;
    return Map<String, dynamic>.from(task);
  }

  Future<Map<String, dynamic>> executeNextStep() async {
    if (_executing) throw StateError('يوجد تنفيذ مهمة جارٍ بالفعل.');
    final task = _tasks.cast<Map<String, dynamic>>().firstWhere(
      (item) => item['id'] == _currentTask,
      orElse: () => <String, dynamic>{},
    );
    if (task.isEmpty) return {'status': 'missing', 'message': 'لا توجد مهمة نشطة.'};
    if (task['status'] == 'completed') return {'status': 'completed', 'task_summary': task};

    _executing = true;
    final step = (task['steps'] as List).first as Map<String, dynamic>;
    task['status'] = 'running';
    task['started_at'] ??= DateTime.now().toIso8601String();
    step['status'] = 'running';
    try {
      final result = await _agent.runTask(task['description'] as String);
      step['status'] = 'completed';
      step['result'] = result;
      task['status'] = 'completed';
      task['completed_at'] = DateTime.now().toIso8601String();
      task['result'] = result;
      return {
        'status': 'completed',
        'step': step['step'],
        'action': step['action'],
        'result': result,
        'remaining': 0,
        'task_summary': Map<String, dynamic>.from(task),
      };
    } catch (error) {
      step['status'] = 'failed';
      step['error'] = error.toString();
      task['status'] = 'failed';
      task['error'] = error.toString();
      return {'status': 'failed', 'error': error.toString(), 'task_summary': task};
    } finally {
      _executing = false;
    }
  }

  Future<bool> cancelTask() async {
    if (!_executing) return false;
    return _agent.cancel();
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
            : status == 'running'
                ? 'قيد التنفيذ'
                : 'بانتظار التنفيذ';
  }

  List<Map<String, dynamic>> getTasks() =>
      _tasks.map((task) => Map<String, dynamic>.from(task)).toList(growable: false);

  void clearTasks() {
    if (_executing) throw StateError('لا يمكن مسح المهام أثناء التنفيذ.');
    _tasks.clear();
    _currentTask = '';
  }
}
