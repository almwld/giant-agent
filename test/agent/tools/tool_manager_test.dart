import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/tools/tool_manager.dart';

void main() {
  group('ToolManager registry', () {
    final registry = ToolManager();

    test('exposes only tools implemented by the runtime', () {
      expect(
        registry.getAvailableTools(),
        ['create_file', 'read_file', 'write_file', 'list_files', 'execute_python', 'mcp_read_resource', 'mcp_call', 'create_subagent', 'spawn_subagent', 'delete_subagent', 'check_subagent_status', 'send_message', 'wait_for_message', 'ask_user', 'update_goal', 'gain_terminal'],
      );
      expect(registry.supports('delete_file'), isFalse);
      expect(registry.supports('execute_python'), isTrue);
      expect(registry.supports('gain_terminal'), isTrue);
      expect(registry.supports('create_subagent'), isTrue);
      expect(registry.supports('spawn_subagent'), isTrue);
      expect(registry.supports('ask_user'), isTrue);
      expect(registry.supports('update_goal'), isTrue);
    });

    test('builds prompt catalogue from the registered definitions', () {
      final catalogue = registry.promptCatalog;
      expect(catalogue, contains('create_file'));
      expect(catalogue, contains('read_file'));
      expect(catalogue, contains('write_file'));
      expect(catalogue, contains('execute_python'));
      expect(catalogue, contains('gain_terminal'));
      expect(catalogue, contains('list_files'));
      expect(catalogue, contains('create_subagent'));
      expect(catalogue, contains('spawn_subagent'));
      expect(catalogue, contains('delete_subagent'));
      expect(catalogue, contains('check_subagent_status'));
      expect(catalogue, contains('send_message'));
      expect(catalogue, contains('wait_for_message'));
      expect(catalogue, contains('ask_user'));
      expect(catalogue, contains('update_goal'));
      expect(catalogue, contains('\n'));
      expect(catalogue, isNot(contains(r'\n  مثال:')));
    });
  });
}
