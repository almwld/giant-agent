import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/tools/tool_manager.dart';

void main() {
  group('ToolManager registry', () {
    final registry = ToolManager();

    test('exposes only tools implemented by the runtime', () {
      expect(
        registry.getAvailableTools(),
        ['create_file', 'read_file', 'write_file', 'execute_python'],
      );
      expect(registry.supports('delete_file'), isFalse);
      expect(registry.supports('execute_python'), isTrue);
    });

    test('builds prompt catalogue from the registered definitions', () {
      final catalogue = registry.promptCatalog;
      expect(catalogue, contains('create_file'));
      expect(catalogue, contains('read_file'));
      expect(catalogue, contains('write_file'));
      expect(catalogue, contains('execute_python'));
      expect(catalogue, contains('\n'));
      expect(catalogue, isNot(contains(r'\n  مثال:')));
    });
  });
}
