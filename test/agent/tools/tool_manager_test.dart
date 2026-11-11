import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/tools/tool_manager.dart';

void main() {
  group('ToolManager registry', () {
    final registry = ToolManager();

    test('exposes only tools implemented by the runtime', () {
      expect(
        registry.getAvailableTools(),
        ['create_file', 'read_file', 'write_file', 'list_files', 'execute_python', 'mcp_read_resource', 'mcp_call', 'create_subagent', 'spawn_subagent', 'delete_subagent', 'check_subagent_status', 'send_message', 'wait_for_message', 'ask_user', 'update_goal', 'web_search', 'todo_read', 'todo_write', 'memory_space_insert', 'memory_space_update', 'memory_space_delete', 'memory_space_edits', 'generate_speech', 'get_available_voices', 'get_data_source', 'get_data_source_desc', 'generate_slides_outline', 'slides_generator', 'fetch_urls', 'visit', 'click', 'input', 'find', 'scrollup', 'scrolldown', 'browser_visit', 'browser_click', 'browser_find', 'browser_input', 'browser_state', 'browser_scroll_up', 'browser_scroll_down', 'gain_terminal'],
      );
      expect(registry.supports('delete_file'), isFalse);
      expect(registry.supports('execute_python'), isTrue);
      expect(registry.supports('gain_terminal'), isTrue);
      expect(registry.supports('create_subagent'), isTrue);
      expect(registry.supports('spawn_subagent'), isTrue);
      expect(registry.supports('ask_user'), isTrue);
      expect(registry.supports('update_goal'), isTrue);
      expect(registry.supports('web_search'), isTrue);
      expect(registry.supports('memory_space_insert'), isTrue);
      expect(registry.supports('generate_speech'), isTrue);
      expect(registry.supports('slides_generator'), isTrue);
      expect(registry.supports('browser_visit'), isTrue);
      expect(registry.supports('browser_click'), isTrue);
      expect(registry.supports('browser_input'), isTrue);
      expect(registry.supports('browser_state'), isTrue);
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
      expect(catalogue, contains('web_search'));
      expect(catalogue, contains('todo_read'));
      expect(catalogue, contains('todo_write'));
      expect(catalogue, contains('memory_space_insert'));
      expect(catalogue, contains('memory_space_update'));
      expect(catalogue, contains('memory_space_delete'));
      expect(catalogue, contains('memory_space_edits'));
      expect(catalogue, contains('generate_speech'));
      expect(catalogue, contains('get_available_voices'));
      expect(catalogue, contains('get_data_source'));
      expect(catalogue, contains('get_data_source_desc'));
      expect(catalogue, contains('generate_slides_outline'));
      expect(catalogue, contains('slides_generator'));
      expect(catalogue, contains('fetch_urls'));
      expect(catalogue, contains('visit'));
      expect(catalogue, contains('click'));
      expect(catalogue, contains('input'));
      expect(catalogue, contains('find'));
      expect(catalogue, contains('scrollup'));
      expect(catalogue, contains('scrolldown'));
      expect(catalogue, contains('browser_visit'));
      expect(catalogue, contains('browser_click'));
      expect(catalogue, contains('browser_find'));
      expect(catalogue, contains('browser_input'));
      expect(catalogue, contains('browser_state'));
      expect(catalogue, contains('browser_scroll_up'));
      expect(catalogue, contains('browser_scroll_down'));
      expect(catalogue, contains('\n'));
      expect(catalogue, isNot(contains(r'\n  مثال:')));
    });
  });
}
