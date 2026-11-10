import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/domain/harness/reflexion_service.dart';

void main() {
  group('ReflexionService', () {
    test('parses and allow-lists a corrective workspace listing action', () async {
      final service = ReflexionService(
        generate: (_) async => '{"tool":"list_files","args":{}}',
      );
      final action = await service.generateFix(
        originalGoal: 'Read nonexistent.txt',
        failedAction: '{"name":"read_file","arguments":{"path":"nonexistent.txt"}}',
        errorMessage: 'File does not exist.',
      );
      expect(action.toolName, 'list_files');
      expect(action.arguments, isEmpty);
    });

    test('rejects a tool outside the registry', () async {
      final service = ReflexionService(
        generate: (_) async => '{"tool":"execute_terminal","args":{"command":"ls"}}',
      );
      await expectLater(
        service.generateFix(
          originalGoal: 'Inspect files',
          failedAction: 'read_file',
          errorMessage: 'not found',
        ),
        throwsFormatException,
      );
    });

    test('rejects malformed model output', () async {
      final service = ReflexionService(generate: (_) async => 'I will try another action.');
      await expectLater(
        service.generateFix(
          originalGoal: 'Inspect files',
          failedAction: 'read_file',
          errorMessage: 'not found',
        ),
        throwsFormatException,
      );
    });

    test('includes the original failure and available tools in the repair prompt', () async {
      var prompt = '';
      final service = ReflexionService(generate: (value) async {
        prompt = value;
        return '{"tool":"list_files","args":{}}';
      });
      await service.generateFix(
        originalGoal: 'Read nonexistent.txt',
        failedAction: 'read_file nonexistent.txt',
        errorMessage: 'File does not exist',
      );
      expect(prompt, contains('Read nonexistent.txt'));
      expect(prompt, contains('File does not exist'));
      expect(prompt, contains('list_files'));
    });
  });
}
