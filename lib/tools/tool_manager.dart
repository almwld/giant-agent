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
      name: 'mcp_read_resource',
      description: 'قراءة مورد أو ملف من خادم MCP باستخدام URI مطلق أعاده الخادم أو أحد أدواته.',
      example: '{"name":"mcp_read_resource","arguments":{"server_id":"workspace","uri":"file:///report.pdf"}}',
    ),
    AgentToolDefinition(
      name: 'mcp_call',
      description: 'استدعاء أداة مكتشفة من خادم MCP متصل. استخدم server_id وtool_name كما يظهران في قائمة أدوات MCP، وأرسل arguments وفق مخطط الأداة.',
      example: '{"name":"mcp_call","arguments":{"server_id":"workspace","tool_name":"search","arguments":{"query":"..."}}}',
    ),
    AgentToolDefinition(
      name: 'create_subagent',
      description: 'تسجيل وكيل فرعي دائم دون تشغيله. يتطلب id وtitle وprompt، ويمكن تحديد agent_type من explore أو plan أو coder أو reviewer وdepends_on لمعرفات وكلاء من الطلب نفسه.',
      example: '{"name":"create_subagent","arguments":{"id":"research_api","title":"استكشاف واجهة API","prompt":"افحص ملفات API وحدد نقاط التكامل دون تعديل الملفات.","agent_type":"explore","depends_on":[]}}',
    ),
    AgentToolDefinition(
      name: 'spawn_subagent',
      description: 'تشغيل وكيل فرعي مسجل بحالة pending. التشغيل مستقل عن التسجيل، ولا يبدأ قبل اكتمال كل التبعيات.',
      example: '{"name":"spawn_subagent","arguments":{"task_id":"research_api"}}',
    ),
    AgentToolDefinition(
      name: 'check_subagent_status',
      description: 'قراءة الحالة والنتيجة المحفوظة لوكيل فرعي تابع للطلب الحالي.',
      example: '{"name":"check_subagent_status","arguments":{"task_id":"research_api"}}',
    ),
    AgentToolDefinition(
      name: 'list_subagents',
      description: 'عرض قائمة الوكلاء الفرعيين المسجلين للطلب الحالي وحالاتهم ونتائجهم.',
      example: '{"name":"list_subagents","arguments":{}}',
    ),
    AgentToolDefinition(
      name: 'delete_subagent',
      description: 'إخفاء وكيل فرعي نهائي من الإدارة فقط مع الاحتفاظ بسجل التدقيق؛ لا يمكن حذف وكيل pending أو running.',
      example: '{"name":"delete_subagent","arguments":{"task_id":"research_api"}}',
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
