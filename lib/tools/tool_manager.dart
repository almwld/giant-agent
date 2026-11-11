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
      name: 'edit_file',
      description: 'تحديث ملف نصي موجود في مساحة العمل عبر الجسر المقيد؛ لا ينشئ ملفاً جديداً.',
      example: '{"name":"edit_file","arguments":{"path":"lib/example.dart","content":"// revised file"}}',
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
      description: 'تسجيل وكيل فرعي جديد دون تشغيله. استخدم id وtitle وprompt وagent_type وdepends_on؛ لا ينشئ الوكيل الفرعي وكلاء آخرين.',
      example: '{"name":"create_subagent","arguments":{"id":"research","title":"بحث","prompt":"افحص مصادر المشروع ذات الصلة","agent_type":"explore","depends_on":[]}}',
    ),
    AgentToolDefinition(
      name: 'spawn_subagent',
      description: 'تشغيل وكيل مسجل مسبقاً عبر محرك النموذج الحالي المشترك، مع احترام التبعيات وصلاحيات الدور.',
      example: '{"name":"spawn_subagent","arguments":{"id":"research"}}',
    ),
    AgentToolDefinition(
      name: 'delete_subagent',
      description: 'إخفاء وكيل غير نشط من الإدارة مع الاحتفاظ بسجل التدقيق؛ لا يحذف الملفات ولا يمحو التاريخ.',
      example: '{"name":"delete_subagent","arguments":{"id":"research"}}',
    ),
    AgentToolDefinition(
      name: 'check_subagent_status',
      description: 'قراءة حالة وكيل فرعي ونتيجته المحفوظة ضمن الطلب الحالي.',
      example: '{"name":"check_subagent_status","arguments":{"id":"research"}}',
    ),
    AgentToolDefinition(
      name: 'send_message',
      description: 'إرسال رسالة إلى صندوق وارد وكيل فرعي مسجل؛ يمكن إرسالها قبل تشغيله.',
      example: '{"name":"send_message","arguments":{"agent_id":"research","message":"ركز على اختبارات الاستعادة"}}',
    ),
    AgentToolDefinition(
      name: 'wait_for_message',
      description: 'انتظار رسالة في صندوق وارد وكيل فرعي لمدة محدودة لا تتجاوز 30 ثانية.',
      example: '{"name":"wait_for_message","arguments":{"agent_id":"research","timeout_seconds":10}}',
    ),
    AgentToolDefinition(
      name: 'ask_user',
      description: 'طلب توضيح مباشر من المستخدم عبر نافذة التطبيق؛ لا يخترع إجابة إذا لم تتوفر واجهة السؤال.',
      example: '{"name":"ask_user","arguments":{"question":"أي فرع هو الهدف؟","choices":["main","integration"]}}',
    ),
    AgentToolDefinition(
      name: 'update_goal',
      description: 'تحديث هدف الطلب الجاري؛ يظهر التحديث في سجل الأحداث ويستخدمه الوكلاء اللاحقون.',
      example: '{"name":"update_goal","arguments":{"goal":"أكمل التكامل ثم شغّل الاختبارات"}}',
    ),
    AgentToolDefinition(
      name: 'web_search',
      description: 'البحث على الويب عبر DuckDuckGo وإرجاع عناوين وروابط ومقتطفات فعلية.',
      example: '{"name":"web_search","arguments":{"query":"Flutter 3.16 release notes","limit":5}}',
    ),
    AgentToolDefinition(
      name: 'todo_read',
      description: 'قراءة المهام المحلية الدائمة للجلسة الحالية وحالاتها.',
      example: '{"name":"todo_read","arguments":{"status":"pending"}}',
    ),
    AgentToolDefinition(
      name: 'todo_write',
      description: 'إنشاء عنصر مهمة محلي دائم دون بدء تنفيذه تلقائياً.',
      example: '{"name":"todo_write","arguments":{"description":"مراجعة اختبارات MCP"}}',
    ),
    AgentToolDefinition(
      name: 'memory_space_insert',
      description: 'حفظ حقيقة محلية صريحة بمفتاح وقيمة وأهمية من 1 إلى 5 مع تسجيل أثر التغيير.',
      example: '{"name":"memory_space_insert","arguments":{"key":"preferred_language","value":"Arabic","importance":3}}',
    ),
    AgentToolDefinition(
      name: 'memory_space_update',
      description: 'تحديث حقيقة محلية موجودة مع الاحتفاظ بالقيمة السابقة في سجل التعديلات.',
      example: '{"name":"memory_space_update","arguments":{"key":"preferred_language","value":"Modern Standard Arabic"}}',
    ),
    AgentToolDefinition(
      name: 'memory_space_delete',
      description: 'حذف حقيقة محلية محددة مع تسجيل عملية الحذف؛ لا يمسح سجل المحادثات.',
      example: '{"name":"memory_space_delete","arguments":{"key":"temporary_note"}}',
    ),
    AgentToolDefinition(
      name: 'memory_space_edits',
      description: 'عرض سجل عمليات إدخال وتحديث وحذف الحقائق المحلية.',
      example: '{"name":"memory_space_edits","arguments":{"limit":50}}',
    ),
    AgentToolDefinition(
      name: 'generate_speech',
      description: 'قراءة نص بصوت الجهاز عبر Flutter TTS؛ لا ينشئ ملفاً صوتياً قابلاً للتنزيل.',
      example: '{"name":"generate_speech","arguments":{"text":"مرحباً بك في Giant Agent"}}',
    ),
    AgentToolDefinition(
      name: 'get_available_voices',
      description: 'عرض أصوات TTS المثبتة والمتاحة على الجهاز.',
      example: '{"name":"get_available_voices","arguments":{}}',
    ),
    AgentToolDefinition(
      name: 'get_data_source',
      description: 'عرض خوادم MCP التي ربطها المستخدم دون كشف رموز الوصول.',
      example: '{"name":"get_data_source","arguments":{}}',
    ),
    AgentToolDefinition(
      name: 'get_data_source_desc',
      description: 'قراءة وصف خادم MCP وأدواته وموارده بعد تهيئة الاتصال.',
      example: '{"name":"get_data_source_desc","arguments":{"server_id":"local_docs"}}',
    ),
    AgentToolDefinition(
      name: 'generate_slides_outline',
      description: 'إنشاء مخطط شرائح منظم باستخدام النموذج الحالي؛ لا يدّعي إنشاء PowerPoint.',
      example: '{"name":"generate_slides_outline","arguments":{"topic":"Agent architecture","slides":8}}',
    ),
    AgentToolDefinition(
      name: 'slides_generator',
      description: 'إنشاء عرض HTML محلي قابل للتنقل من قائمة شرائح منظمة داخل مساحة العمل.',
      example: '{"name":"slides_generator","arguments":{"path":"presentations/overview.html","title":"Overview","slides":[{"title":"Goal","body":"Key points"}]}}',
    ),
    AgentToolDefinition(
      name: 'fetch_urls',
      description: 'فتح ما يصل إلى خمسة روابط HTTP(S) في جلسة المتصفح المرئية وجلب عنوان الصفحة ونصها.',
      example: '{"name":"fetch_urls","arguments":{"urls":["https://example.com"]}}',
    ),
    AgentToolDefinition(
      name: 'visit',
      description: 'فتح رابط في متصفح الوكيل المرئي.',
      example: '{"name":"visit","arguments":{"url":"https://example.com"}}',
    ),
    AgentToolDefinition(
      name: 'click',
      description: 'النقر على رابط أو زر بحسب النص الظاهر المطابق.',
      example: '{"name":"click","arguments":{"text":"Sign in"}}',
    ),
    AgentToolDefinition(
      name: 'input',
      description: 'إدخال قيمة في عنصر نموذج يحدده CSS selector؛ لا يرسل النموذج تلقائياً.',
      example: '{"name":"input","arguments":{"selector":"input[name=email]","value":"user@example.com"}}',
    ),
    AgentToolDefinition(
      name: 'find',
      description: 'البحث عن نص داخل محتوى الصفحة الحالية وإرجاع مقتطف حول التطابق.',
      example: '{"name":"find","arguments":{"query":"pricing"}}',
    ),
    AgentToolDefinition(
      name: 'scrollup',
      description: 'تمرير صفحة المتصفح المرئية إلى أعلى.',
      example: '{"name":"scrollup","arguments":{}}',
    ),
    AgentToolDefinition(
      name: 'scrolldown',
      description: 'تمرير صفحة المتصفح المرئية إلى أسفل.',
      example: '{"name":"scrolldown","arguments":{}}',
    ),
    AgentToolDefinition(
      name: 'browser_visit',
      description: 'فتح رابط HTTP(S) في جلسة المتصفح المرئية للمستخدم.',
      example: '{"name":"browser_visit","arguments":{"url":"https://example.com"}}',
    ),
    AgentToolDefinition(
      name: 'browser_click',
      description: 'النقر على رابط أو زر في صفحة المتصفح بحسب النص الظاهر.',
      example: '{"name":"browser_click","arguments":{"text":"Continue"}}',
    ),
    AgentToolDefinition(
      name: 'browser_find',
      description: 'البحث عن نص داخل الصفحة الحالية.',
      example: '{"name":"browser_find","arguments":{"query":"terms and conditions"}}',
    ),
    AgentToolDefinition(
      name: 'browser_input',
      description: 'ملء عنصر إدخال محدد في صفحة المتصفح دون إرسال النموذج.',
      example: '{"name":"browser_input","arguments":{"selector":"textarea[name=message]","value":"Hello"}}',
    ),
    AgentToolDefinition(
      name: 'browser_state',
      description: 'قراءة عنوان URL والعنوان ونص الصفحة الحالية.',
      example: '{"name":"browser_state","arguments":{}}',
    ),
    AgentToolDefinition(
      name: 'browser_scroll_up',
      description: 'تمرير صفحة المتصفح المرئية إلى أعلى.',
      example: '{"name":"browser_scroll_up","arguments":{}}',
    ),
    AgentToolDefinition(
      name: 'browser_scroll_down',
      description: 'تمرير صفحة المتصفح المرئية إلى أسفل.',
      example: '{"name":"browser_scroll_down","arguments":{}}',
    ),
    AgentToolDefinition(
      name: 'image_search',
      description: 'البحث عن الصور عبر مزوّد صور متصل؛ لا يستخدم بحث الويب النصي بديلاً عن نتائج الصور.',
      example: '{"name":"image_search","arguments":{"query":"teal glass orb"}}',
    ),
    AgentToolDefinition(
      name: 'search_image_by_text',
      description: 'البحث عن صور باستخدام وصف نصي عبر مزوّد صور متصل.',
      example: '{"name":"search_image_by_text","arguments":{"query":"minimal dark AI dashboard"}}',
    ),
    AgentToolDefinition(
      name: 'search_image_by_image',
      description: 'البحث العكسي عن صور باستخدام ملف مصدر ومزوّد يدعم البحث البصري.',
      example: '{"name":"search_image_by_image","arguments":{"input_path":"images/reference.png"}}',
    ),
    AgentToolDefinition(
      name: 'generate_image',
      description: 'توليد صورة عبر مزوّد صور متصل فعلياً؛ لا يفترض أن OpenRouter النصي يولّد الصور.',
      example: '{"name":"generate_image","arguments":{"prompt":"A clean teal glass sphere on a dark background"}}',
    ),
    AgentToolDefinition(
      name: 'edit_image',
      description: 'تعديل صورة مصدر عبر مزوّد يدعم تحرير الصور؛ يتطلب input_path أو input_paths.',
      example: '{"name":"edit_image","arguments":{"prompt":"Remove the background","input_path":"images/source.png"}}',
    ),
    AgentToolDefinition(
      name: 'generate_sound_effects',
      description: 'توليد مؤثرات صوتية عبر مزوّد صوت متصل؛ لا يخلط ذلك مع TTS.',
      example: '{"name":"generate_sound_effects","arguments":{"prompt":"Short soft notification chime"}}',
    ),
    AgentToolDefinition(
      name: 'find_asset_bbox',
      description: 'تحديد صناديق الأصول داخل صورة مصدر عبر مزوّد رؤية متصل.',
      example: '{"name":"find_asset_bbox","arguments":{"input_path":"images/screen.png","prompt":"Find the main card and icon bounds"}}',
    ),
    AgentToolDefinition(
      name: 'crop_and_replicate_assets_in_image',
      description: 'قص وإعادة إنتاج عناصر من صورة مصدر عبر مزوّد تحرير صور متصل.',
      example: '{"name":"crop_and_replicate_assets_in_image","arguments":{"input_path":"images/screen.png","prompt":"Extract the icon and create a clean transparent copy"}}',
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
