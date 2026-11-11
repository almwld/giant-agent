/// Model-facing adapter for the durable subagent lifecycle.
///
/// The adapter keeps ModelService independent from AgentService and avoids a
/// circular service dependency. Handlers are registered by AgentService once
/// its durable store and execution kernel are initialized.
typedef SubagentToolHandler = Future<Map<String, dynamic>> Function(
  String parentRequestId,
  Map<String, dynamic> arguments,
  String toolCallId,
);

class SubagentToolBridge {
  SubagentToolBridge._();

  static final SubagentToolBridge instance = SubagentToolBridge._();

  SubagentToolHandler? _create;
  SubagentToolHandler? _spawn;
  SubagentToolHandler? _check;
  SubagentToolHandler? _delete;
  SubagentToolHandler? _list;

  void configure({
    required SubagentToolHandler create,
    required SubagentToolHandler spawn,
    required SubagentToolHandler check,
    required SubagentToolHandler delete,
    required SubagentToolHandler list,
  }) {
    _create = create;
    _spawn = spawn;
    _check = check;
    _delete = delete;
    _list = list;
  }

  Future<Map<String, dynamic>> invoke({
    required String name,
    required String parentRequestId,
    required Map<String, dynamic> arguments,
    required String toolCallId,
  }) async {
    final parent = parentRequestId.trim();
    if (parent.isEmpty) {
      throw StateError('A durable parent request is required for subagent tools.');
    }
    final handler = switch (name) {
      'create_subagent' => _create,
      'spawn_subagent' => _spawn,
      'check_subagent_status' => _check,
      'delete_subagent' => _delete,
      'list_subagents' => _list,
      _ => null,
    };
    if (handler == null) {
      throw StateError('Subagent tool bridge is not configured for "$name".');
    }
    return handler(parent, Map<String, dynamic>.unmodifiable(arguments), toolCallId);
  }
}
