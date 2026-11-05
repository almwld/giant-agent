import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:giant_agent_x/agent/task_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('recovers interrupted task and running step as paused and pending', () async {
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

    final manager = TaskManager();
    expect(await manager.selectTask('task-recovery-1'), isTrue);

    final recovered = manager.getTasks().single;
    expect(recovered['status'], 'paused');
    expect(recovered['recovery_note'], isNotEmpty);
    expect((recovered['steps'] as List).single['status'], 'pending');
    expect(manager.getProgress(), 'متوقف مؤقتاً — قابل للاستئناف');

    final preferences = await SharedPreferences.getInstance();
    final persisted = jsonDecode(
      preferences.getString('giant_agent.tasks.v1')!,
    ) as List;
    expect((persisted.single as Map)['status'], 'paused');

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
  });
}
