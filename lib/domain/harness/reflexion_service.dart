import 'dart:convert';

import '../../tools/tool_manager.dart';

class ReflexionAction {
  const ReflexionAction({required this.toolName, required this.arguments, required this.rawResponse});
  final String toolName;
  final Map<String, dynamic> arguments;
  final String rawResponse;
}

/// Produces one bounded corrective action. It never executes tools.
class ReflexionService {
  ReflexionService({
    required Future<String> Function(String prompt) generate,
    ToolManager? tools,
  }) : _generate = generate, _tools = tools ?? ToolManager();

  final Future<String> Function(String prompt) _generate;
  final ToolManager _tools;

  Future<ReflexionAction> generateFix({
    required String originalGoal,
    required String failedAction,
    required String errorMessage,
  }) async {
    final prompt = '''
You are the recovery controller for Giant Agent.
User goal: $originalGoal
Failed tool action: $failedAction
Independent verification: $errorMessage

Choose one different, safe next tool action from this exact allow-list:
${_tools.promptCatalog}

Do not repeat the failed action. Prefer list_files to discover valid workspace paths when read_file cannot find a path. Do not invent tools, paths, file contents, or successful outcomes.
Return ONLY one JSON object:
{"tool":"tool_name","args":{...}}
No markdown, explanation, or private reasoning.
''';
    final raw = (await _generate(prompt)).trim();
    final decoded = _decodeObject(raw);
    final tool = decoded['tool']?.toString() ?? '';
    final args = decoded['args'];
    if (!_tools.supports(tool) || args is! Map) {
      throw const FormatException('Reflexion returned an unsupported tool or invalid arguments.');
    }
    final normalized = <String, dynamic>{};
    for (final entry in args.entries) {
      if (entry.key is! String) throw const FormatException('Reflexion argument names must be strings.');
      normalized[entry.key as String] = entry.value;
    }
    _validateArguments(tool, normalized);
    return ReflexionAction(toolName: tool, arguments: normalized, rawResponse: raw);
  }

  void _validateArguments(String tool, Map<String, dynamic> args) {
    bool hasText(String key) => args[key] is String && (args[key] as String).trim().isNotEmpty;
    switch (tool) {
      case 'create_file':
      case 'write_file':
        if (!hasText('path') || args['content'] is! String) {
          throw FormatException('Reflexion action "$tool" requires a non-empty path and string content.');
        }
        break;
      case 'read_file':
        if (!hasText('path')) {
          throw const FormatException('Reflexion read_file action requires a non-empty path.');
        }
        break;
      case 'execute_python':
        if (!hasText('code')) {
          throw const FormatException('Reflexion execute_python action requires non-empty code.');
        }
        break;
      case 'list_files':
        if (args.isNotEmpty) {
          throw const FormatException('Reflexion list_files action does not accept arguments.');
        }
        break;
      default:
        throw FormatException('Reflexion action "$tool" is not supported.');
    }
  }

  Map<String, dynamic> _decodeObject(String raw) {
    try {
      final value = jsonDecode(raw);
      if (value is Map<String, dynamic>) return value;
    } on FormatException {
      // Extract a single JSON object from harmless surrounding text.
    }
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(raw);
    if (match == null) throw const FormatException('Reflexion did not return JSON.');
    final value = jsonDecode(match.group(0)!);
    if (value is! Map<String, dynamic>) throw const FormatException('Reflexion response must be a JSON object.');
    return value;
  }
}
