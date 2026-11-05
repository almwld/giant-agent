import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/services/planner_service.dart';

void main() {
  group('PlannerService', () {
    final planner = PlannerService();
    test('does not plan ordinary conversational prompts', () {
      expect(planner.requiresPlan('ما عاصمة اليمن؟'), isFalse);
      expect(planner.requiresPlan('مرحبا'), isFalse);
    });
    test('recognizes multi-step software requests', () {
      expect(planner.requiresPlan('أنشئ تطبيقاً لإدارة المهام'), isTrue);
      expect(planner.requiresPlan('Build a website and then review its files'), isTrue);
    });
    test('recognizes integrated kernel, memory and recovery work', () {
      const request = 'أكمل إغلاق فجوات التكامل في النواة والذاكرة والتخطيط والاستعادة، ثم تحقق من دورة عمل الوكيل على الجهاز';
      expect(planner.requiresPlan(request), isTrue);
      final plan = planner.createPlan(request);
      expect(plan.length, 5);
      expect(plan.first['action'], contains('فحص بنية المشروع'));
      expect(plan.last['action'], contains('التحقق من دورة العمل'));
    });
    test('creates deterministic inspectable software steps', () {
      final plan = planner.createPlan('أنشئ تطبيقاً لإدارة المهام');
      expect(plan.length, 5);
      expect(plan.first['step'], 1);
      expect(plan.first['status'], 'pending');
      expect(plan.map((item) => item['step']).toList(), [1, 2, 3, 4]);
    });
    test('rejects empty requests', () {
      expect(() => planner.createPlan('  '), throwsArgumentError);
    });
  });
}
