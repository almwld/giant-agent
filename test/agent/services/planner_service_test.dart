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
    test('creates deterministic inspectable software steps', () {
      final plan = planner.createPlan('أنشئ تطبيقاً لإدارة المهام');
      expect(plan.length, 4);
      expect(plan.first['step'], 1);
      expect(plan.first['status'], 'pending');
      expect(plan.map((item) => item['step']).toList(), [1, 2, 3, 4]);
    });
    test('rejects empty requests', () {
      expect(() => planner.createPlan('  '), throwsArgumentError);
    });
  });
}
