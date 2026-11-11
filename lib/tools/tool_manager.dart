/// Canonical registry of tools exposed to the agent model.
///
/// The registry is the single source for the model-facing tool catalogue and
/// the runtime allow-list. Actual platform execution remains in ModelService,
/// which owns the native MethodChannel boundary.
class AgentToolDefinition {
  const AgentToolDefinition({
    required this.name,
    required this.description,
    required this.example,
  });

  final String name;
  final String description;
  final String example;
}

class ToolManager {
  ToolManager._internal();

  static final ToolManager _instance = ToolManager._internal();
  factory ToolManager() => _instance;

  static const List<AgentToolDefinition> _definitions = [
    AgentToolDefinition(
      name: 'create_file',
      description: 'إنشاء ملف جديد فقط داخل مساحة العمل؛ لا يستبدل ملفاً موجوداً.',
      example: '{"name":"create_file","arguments":{"path":"index.html","content":"<!doctype html>..."}}',
    ),
    AgentToolDefinition(
      name: 'read_file',
      description: 'قراءة محتوى ملف موجود داخل مساحة العمل.',
      example: '{"name":"read_file","arguments":{"path":"index.html"}}',
    ),
    AgentToolDefinition(
      name: 'write_file',
      description: 'تحديث ملف موجود داخل مساحة العمل مع التحقق من المسار والحجم.',
      example: '{"name":"write_file","arguments":{"path":"index.html","content":"..."}}',
    ),
    AgentToolDefinition(
      name: 'list_files',
      description: 'عرض أسماء الملفات الموجودة داخل مساحة العمل لاكتشاف المسارات الصحيحة.',
      example: '{"name":"list_files","arguments":{}}',
    ),
    AgentToolDefinition(
      name: 'execute_python',
      description: 'تنفيذ Python محلي مقيّد للحساب والطباعة والحلقات المحدودة؛ لا يدعم الاستيراد أو فتح الملفات أو الوصول إلى النظام.',
      example: '{"name":"execute_python","arguments":{"code":"for i in range(1, 4):\n    print(i)"}}',
    ),
    AgentToolDefinition(
      name: 'mcp_call',
      description: 'استدعاء أداة مكتشفة من خادم MCP متصل. استخدم server_id وtool_name كما يظهران في قائمة أدوات MCP، وأرسل arguments وفق مخطط الأداة.',
      example: '{"name":"mcp_call","arguments":{"server_id":"workspace","tool_name":"search","arguments":{"query":"..."}}}',
    ),
    AgentToolDefinition(
      name: 'gain_terminal',
      description: 'تنفيذ أمر واحد في Android shell بصلاحيات التطبيق فقط؛ يتطلب موافقة المستخدم الصريحة على نص الأمر حرفياً قبل التنفيذ.',
      example: '{"name":"gain_terminal","arguments":{"command":"pwd && ls","timeout_seconds":30}}',
    ),
  ];

  List<AgentToolDefinition> get definitions =>
      List<AgentToolDefinition>.unmodifiable(_definitions);

  List<String> getAvailableTools() =>
      List<String>.unmodifiable(_definitions.map((tool) => tool.name));

  bool supports(String name) =>
      _definitions.any((tool) => tool.name == name);

  AgentToolDefinition? definitionFor(String name) {
    for (final definition in _definitions) {
      if (definition.name == name) return definition;
    }
    return null;
  }

  /// Text inserted into the model system prompt from the same definitions
  /// used by runtime validation.
  String get promptCatalog => promptCatalogFor(getAvailableTools().toSet());

  String promptCatalogFor(Set<String> allowedTools) => _definitions
      .where((tool) => allowedTools.contains(tool.name))
      .map((tool) => '- ${tool.name}: ${tool.description}\n  مثال: ${tool.example}')
      .join('\n');
}
