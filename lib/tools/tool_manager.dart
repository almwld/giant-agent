import '../services/model_service.dart';

/// Registry for tools that are genuinely implemented by the local runtime.
/// Unsupported legacy mock tools are intentionally not advertised.
class ToolManager {
  ToolManager._internal();
  static final ToolManager _instance = ToolManager._internal();
  factory ToolManager() => _instance;

  final ModelService _models = ModelService();
  late final Map<String, Future<String> Function(Map<String, dynamic>)> _tools = {
    'create_file': (args) async {
      final result = await _models.createFile(
        path: args['path']?.toString() ?? '',
        content: args['content']?.toString() ?? '',
      );
      return 'Created ${result['path'] ?? args['path']}';
    },
    'read_file': (args) async {
      final result = await _models.readFile(path: args['path']?.toString() ?? '');
      return result['content']?.toString() ?? '';
    },
    'write_file': (args) async {
      final result = await _models.writeFile(
        path: args['path']?.toString() ?? '',
        content: args['content']?.toString() ?? '',
      );
      return 'Updated ${result['path'] ?? args['path']}';
    },
    'execute_python': (args) async {
      final result = await _models.executePython(code: args['code']?.toString() ?? '');
      if (result['ok'] != true) {
        throw StateError(result['error']?.toString() ?? 'Python execution failed.');
      }
      return result['output']?.toString() ?? '';
    },
  };

  void registerTools() {
    // The registry is initialized lazily and contains only runtime-backed tools.
  }

  List<String> getAvailableTools() => List.unmodifiable(_tools.keys);

  Future<String> executeTool(String name, Map<String, dynamic> arguments) async {
    final handler = _tools[name];
    if (handler == null) throw UnsupportedError('Tool is not implemented: $name');
    return handler(arguments);
  }
}
