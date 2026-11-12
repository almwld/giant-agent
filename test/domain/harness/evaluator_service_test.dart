import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/domain/harness/evaluator_service.dart';

void main() {
  group('EvaluatorService', () {
    test('verifies a created file by reading back its exact content', () async {
      final evaluator = EvaluatorService(
        readWorkspaceFile: (path) async => {
          'ok': true,
          'path': path,
          'content': 'Hello',
        },
      );
      final result = await evaluator.verify(
        'Create test.txt with Hello',
        'create_file',
        {'path': 'test.txt', 'content': 'Hello'},
        {'ok': true, 'path': 'test.txt'},
      );
      expect(result.passed, isTrue);
      expect(result.evidence?['content_matches'], isTrue);
    });

    test('rejects a success flag when persisted content differs', () async {
      final evaluator = EvaluatorService(
        readWorkspaceFile: (_) async => {'ok': true, 'content': 'Not Hello'},
      );
      final result = await evaluator.verify(
        'Create test.txt with Hello',
        'create_file',
        {'path': 'test.txt', 'content': 'Hello'},
        {'ok': true},
      );
      expect(result.passed, isFalse);
      expect(result.message, contains('differs'));
    });

    test('rejects a tool failure even if output text sounds successful', () async {
      final evaluator = EvaluatorService(readWorkspaceFile: (_) async => {'ok': true, 'content': 'Hello'});
      final result = await evaluator.verify(
        'Create a file',
        'create_file',
        {'path': 'test.txt', 'content': 'Hello'},
        {'ok': false, 'error': 'Permission denied'},
      );
      expect(result.passed, isFalse);
      expect(result.message, contains('Permission denied'));
    });

    test('requires readable content for read_file', () async {
      final evaluator = EvaluatorService(readWorkspaceFile: (_) async => {'ok': false});
      final result = await evaluator.verify(
        'Read missing.txt',
        'read_file',
        {'path': 'missing.txt'},
        {'ok': true, 'path': 'missing.txt'},
      );
      expect(result.passed, isFalse);
    });

    test('does not claim goal-level Python verification', () async {
      final evaluator = EvaluatorService(readWorkspaceFile: (_) async => {'ok': false});
      final result = await evaluator.verify(
        'Calculate 2 + 2',
        'execute_python',
        {'code': 'print(2 + 2)'},
        {'ok': true, 'output': '4', 'error': ''},
      );
      expect(result.passed, isTrue);
      expect(result.evidence?['goal_semantics_independently_asserted'], isFalse);
    });

    test('rejects tools without an independent verifier', () async {
      final evaluator = EvaluatorService(readWorkspaceFile: (_) async => {'ok': false});
      final result = await evaluator.verify('goal', 'unknown_tool', {}, {'ok': true});
      expect(result.passed, isFalse);
    });
  });
}
