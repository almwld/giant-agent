import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/tools/tool_manager.dart';

void main() {
  test('read-only subagent catalog excludes every write and execution tool', () {
    final catalog = ToolManager().promptCatalogFor(
      const {'read_file', 'list_files'},
    );

    expect(catalog, contains('read_file'));
    expect(catalog, contains('list_files'));
    expect(catalog, isNot(contains('create_file')));
    expect(catalog, isNot(contains('write_file')));
    expect(catalog, isNot(contains('execute_python')));
    expect(catalog, isNot(contains('gain_terminal')));
  });

  test('coder catalog is limited to registered tool definitions', () {
    final allowed = const {'create_file', 'read_file', 'write_file'};
    final catalog = ToolManager().promptCatalogFor(allowed);

    for (final name in allowed) {
      expect(catalog, contains(name));
    }
    expect(catalog, isNot(contains('gain_terminal')));
    expect(ToolManager().supports('unregistered_agent_tool'), isFalse);
  });
}
