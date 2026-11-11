import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/tools/tool_manager.dart';
import 'package:giant_agent_x/agent/architecture/subagent_tool_bridge.dart';

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
  test('registers the complete durable lifecycle as model-facing tools', () {
    for (final name in const [
      'create_subagent',
      'spawn_subagent',
      'check_subagent_status',
      'list_subagents',
      'delete_subagent',
    ]) {
      expect(ToolManager().supports(name), isTrue);
      expect(ToolManager().definitionFor(name), isNotNull);
    }

    final readOnly = ToolManager().promptCatalogFor(
      const {'read_file', 'list_files'},
    );
    expect(readOnly, isNot(contains('create_subagent')));
    expect(readOnly, isNot(contains('spawn_subagent')));
  });

  test('routes lifecycle operations with parent and tool-call identity', () async {
    final observed = <String, Object?>{};
    Future<Map<String, dynamic>> handler(
      String parent,
      Map<String, dynamic> arguments,
      String toolCallId,
      bool Function()? isCancelled,
    ) async {
      observed
        ..['parent'] = parent
        ..['arguments'] = arguments
        ..['tool_call_id'] = toolCallId
        ..['is_cancelled'] = isCancelled?.call() ?? false;
      return <String, dynamic>{'ok': true};
    }

    final bridge = SubagentToolBridge.instance;
    bridge.configure(
      create: handler,
      spawn: handler,
      check: handler,
      delete: handler,
      list: handler,
    );

    final result = await bridge.invoke(
      name: 'create_subagent',
      parentRequestId: 'parent-42',
      arguments: const <String, dynamic>{'id': 'child-7'},
      toolCallId: 'call-9',
      isCancelled: () => true,
    );

    expect(result['ok'], isTrue);
    expect(observed['parent'], 'parent-42');
    expect(observed['arguments'], {'id': 'child-7'});
    expect(observed['tool_call_id'], 'call-9');
    expect(observed['is_cancelled'], isTrue);
  });

  test('rejects subagent calls without parent identity or known operation', () async {
    final bridge = SubagentToolBridge.instance;
    await expectLater(
      bridge.invoke(
        name: 'create_subagent',
        parentRequestId: '',
        arguments: const <String, dynamic>{},
        toolCallId: 'call-empty-parent',
      ),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      bridge.invoke(
        name: 'invented_subagent_action',
        parentRequestId: 'parent-1',
        arguments: const <String, dynamic>{},
        toolCallId: 'call-unknown',
      ),
      throwsA(isA<StateError>()),
    );
  });

}
