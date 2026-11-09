import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:giant_agent_x/agent/task_manager.dart';
import 'package:giant_agent_x/domain/kernel/agent_kernel_store.dart';

Future<AgentKernelStore> _store(String path) async {
  return AgentKernelStore(
    databaseProvider: () => databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) async {
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
            CREATE INDEX idx_agent_tasks_conversation
            ON agent_tasks(conversation_id, sequence)
          ''');
        },
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('classifies task outcomes without treating interruption as completion', () {
    expect(
      TaskManager.classifyResult('تم إيقاف تنفيذ الوكيل بناءً على طلب المستخدم.'),
      TaskExecutionOutcome.interrupted,
    );
    expect(
      TaskManager.classifyResult('وصل الوكيل إلى الحد الآمن دون إنهاء المهمة.'),
      TaskExecutionOutcome.interrupted,
    );
    expect(
      TaskManager.classifyResult('ERROR: تعذر تشغيل النموذج.'),
      TaskExecutionOutcome.failed,
    );
    expect(
      TaskManager.classifyResult('⚠️ اختر نموذج GGUF محلياً أو فعّل OpenRouter.'),
      TaskExecutionOutcome.failed,
    );
    expect(
      TaskManager.classifyResult('اكتملت المهمة والنتيجة جاهزة.'),
      TaskExecutionOutcome.completed,
    );
  });

  test('imports legacy tasks into SQLite and recovers running work as paused', () async {
    final directory = await Directory.systemTemp.createTemp('task-manager-v2-');
    final path = '${directory.path}/tasks.db';
    SharedPreferences.setMockInitialValues({
      'giant_agent.tasks.v1': jsonEncode([
        {
          'id': 'task-recovery-1',
          'description': 'استكمال مهمة محفوظة',
          'conversation_id': 'chat-1',
          'status': 'running',
          'steps': [
            {
              'step': 1,
              'action': 'تنفيذ المهمة',
              'status': 'running',
            },
          ],
        },
      ]),
    });

    final manager = TaskManager.withStore(await _store(path));
    try {
      expect(await manager.selectTask('task-recovery-1'), isTrue);

      final recovered = manager.getTasks().single;
      expect(recovered['status'], 'paused');
      expect(recovered['recovery_note'], isNotEmpty);
      expect((recovered['steps'] as List).single['status'], 'pending');
      expect(manager.getProgress(), 'متوقف مؤقتاً — قابل للاستئناف');

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('giant_agent.tasks.v1'), isNull);

      await manager.markRunning('task-recovery-1');
      expect(manager.getTasks().single['status'], 'running');

      await manager.markInterrupted(
        'task-recovery-1',
        'توقف اختباري قبل الاكتمال.',
      );
      expect(manager.getTasks().single['status'], 'paused');
      expect(
        (manager.getTasks().single['steps'] as List).single['status'],
        'pending',
      );

      await manager.markRunning('task-recovery-1');
      await manager.markCompleted('task-recovery-1', 'النتيجة النهائية');
      final completed = manager.getTasks().single;
      expect(completed['status'], 'completed');
      expect(completed['result'], 'النتيجة النهائية');
      expect((completed['steps'] as List).single['status'], 'completed');

      final homeTask = await manager.createTask(
        'مهمة الشاشة الرئيسية',
        conversationId: 'home',
      );
      final homeTasks = await manager.getTasksForConversation('home');
      expect(homeTasks.single['id'], homeTask['id']);
      expect(homeTasks.single['conversation_id'], 'home');

      // A new manager/store instance must reconstruct the same durable history.
      final restarted = TaskManager.withStore(await _store(path));
      final restored = await restarted.getTasksForConversation('home');
      expect(restored.single['id'], homeTask['id']);
      expect(restored.single['status'], 'pending');
      await restarted.closeForTesting();
    } finally {
      await manager.closeForTesting();
      await directory.delete(recursive: true);
    }
  });

  test('clearTasks deletes durable task snapshots', () async {
    final directory = await Directory.systemTemp.createTemp('task-manager-clear-');
    final path = '${directory.path}/tasks.db';
    final manager = TaskManager.withStore(await _store(path));
    try {
      await manager.createTask('مهمة للحذف');
      expect(manager.getTasks(), hasLength(1));
      await manager.clearTasks();
      expect(manager.getTasks(), isEmpty);

      final restarted = TaskManager.withStore(await _store(path));
      expect(await restarted.getTasksForConversation('global'), isEmpty);
      await restarted.closeForTesting();
    } finally {
      await manager.closeForTesting();
      await directory.delete(recursive: true);
    }
  });
}
