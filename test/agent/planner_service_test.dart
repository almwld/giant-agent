import 'package:flutter_test/flutter_test.dart';
import '../../lib/services/planner_service.dart';

void main() {
  final planner = PlannerService();

  group('PlannerService direct-request routing', () {
    test('answers a simple syntax-fix request without a multi-step plan', () {
      expect(
        planner.requiresPlan(
          'Assume this code has a syntax error and explain how to fix it.',
        ),
        isFalse,
      );
    });

    test('answers a direct factual question without a plan', () {
      expect(
        planner.requiresPlan(
          'What is the difference between a class and an object?',
        ),
        isFalse,
      );
    });

    test('keeps explicit end-to-end work eligible for a plan', () {
      expect(
        planner.requiresPlan(
          'أنشئ تطبيقاً صحياً كاملاً من البداية إلى النهاية على مراحل.',
        ),
        isTrue,
      );
    });
  });
}
