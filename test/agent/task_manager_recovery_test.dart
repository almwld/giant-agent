import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:giant_agent_x/agent/task_manager.dart';
import 'package:giant_agent_x/domain/kernel/agent_kernel_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
  });

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

  test('migrates legacy tasks to SQLite and recovers running tasks safely', () async {
    SharedPreferences.setMockInitialValues({
      'giant_agent.tasks.v1': jsonEncode([
        {
          'id': 'task-recovery-1',
          'description': 'استكمال مهمة محفوظة',
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

    final store = AgentKernelStore(
      databaseProvider: () => databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 3,
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
                created_at TEXT NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TRIGGER agent_events_no_update
              BEFORE UPDATE ON agent_events
              BEGIN SELECT RAISE(ABORT, 'agent_events is append-only'); END
            ''');
            await db.execute('''
              CREATE TRIGGER agent_events_no_delete
              BEFORE DELETE ON agent_events
              BEGIN SELECT RAISE(ABORT, 'agent_events is append-only'); END
            ''');
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
          },
        ),
      ),
    );
    final manager = TaskManager.withStore(store);
    await manager.initialize();

    final recovered = manager.getTasks().single;
    expect(recovered['status'], 'paused');
    expect(recovered['recovery_note'], isNotEmpty);
    expect((recovered['steps'] as List).single['status'], 'uncertain');
    expect(manager.getProgress(), 'متوقف مؤقتاً — قابل للاستئناف');

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('giant_agent.tasks.v1'), isNull);
    final persistedRows = await (await store.database).query('agent_tasks');
    expect(persistedRows, hasLength(1));
    final persistedTask = jsonDecode(
      persistedRows.single['payload_json']! as String,
    ) as Map<String, dynamic>;
    expect(persistedTask['id'], 'task-recovery-1');
    expect(persistedTask['status'], 'paused');

    final recoveryEvents = await store.taskEvents('task-recovery-1');
    expect(recoveryEvents.map((event) => event.type), contains('task_interrupted_on_restart'));
    expect(recoveryEvents.last.payload['replay'], false);
    expect(recoveryEvents.last.payload['policy'], 'manual_reconciliation');

    await manager.markRunning('task-recovery-1', requestId: 'request-recovery-1');
    expect(manager.getTasks().single['status'], 'running');

    await manager.markInterrupted(
      'task-recovery-1',
      'توقف اختباري قبل الاكتمال.',
    );
    expect(manager.getTasks().single['status'], 'paused');
    expect(
      (manager.getTasks().single['steps'] as List).single['status'],
      'uncertain',
    );

    await manager.recordResumeIntent('task-recovery-1');
    await manager.markRunning('task-recovery-1');
    await manager.markCompleted('task-recovery-1', 'النتيجة النهائية');
    final completed = manager.getTasks().single;
    expect(completed['status'], 'completed');
    expect(completed['result'], 'النتيجة النهائية');
    expect((completed['steps'] as List).single['status'], 'completed');

    final lifecycleEvents = await store.taskEvents('task-recovery-1');
    expect(
      lifecycleEvents.map((event) => event.type),
      containsAllInOrder([
        'task_interrupted_on_restart',
        'task_started',
        'step_started',
        'step_interrupted',
        'task_paused',
        'task_resume_requested',
        'task_resumed',
        'step_started',
        'step_completed',
        'task_completed',
      ]),
    );
    final db = await store.database;
    expect(
      db.update('agent_events', {'status': 'tampered'}),
      throwsA(anything),
    );
    expect(db.delete('agent_events'), throwsA(anything));

    final homeTask = await manager.createTask(
      'مهمة الشاشة الرئيسية',
      conversationId: 'home',
    );
    final homeTasks = await manager.getTasksForConversation('home');
    expect(homeTasks.single['id'], homeTask['id']);
    expect(homeTasks.single['conversation_id'], 'home');

    await manager.closeForTesting();
  });
}
