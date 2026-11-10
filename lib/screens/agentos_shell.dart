import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/model_service.dart';
import 'agent_workspace_screen.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

/// AgentOS-inspired navigation shell. The Sehatak palette remains the source
/// of truth; this layer changes presentation, not the agent execution engine.
class AgentOsShell extends StatefulWidget {
  const AgentOsShell({super.key});

  @override
  State<AgentOsShell> createState() => _AgentOsShellState();
}

class _AgentOsShellState extends State<AgentOsShell> {
  int _index = 0;

  static const _pages = <Widget>[
    AgentDashboardPage(),
    AgentWorkflowPage(),
    ChatScreen(),
    AgentStatusPage(),
    AgentIntegrationsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final labels = isArabic
        ? const ['الرئيسية', 'سير العمل', 'المحادثة', 'الوكلاء', 'التكاملات']
        : const ['Overview', 'Workflow', 'Chat', 'Agents', 'Integrations'];
    final icons = const [
      Icons.dashboard_rounded,
      Icons.account_tree_rounded,
      Icons.forum_rounded,
      Icons.smart_toy_rounded,
      Icons.hub_rounded,
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? AppTheme.darkSurface.withOpacity(.96)
                : Colors.white.withOpacity(.97),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppTheme.primary.withOpacity(.18),
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withOpacity(.09),
                blurRadius: 22,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Row(
            children: List.generate(labels.length, (i) {
              final selected = _index == i;
              return Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setState(() => _index = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppTheme.primary.withOpacity(.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icons[i],
                          size: 21,
                          color: selected
                              ? AppTheme.primary
                              : Theme.of(context).colorScheme.onSurface.withOpacity(.55),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          labels[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected
                                ? AppTheme.primary
                                : Theme.of(context).colorScheme.onSurface.withOpacity(.62),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class AgentDashboardPage extends StatefulWidget {
  const AgentDashboardPage({super.key});

  @override
  State<AgentDashboardPage> createState() => _AgentDashboardPageState();
}

class _AgentDashboardPageState extends State<AgentDashboardPage> {
  final ModelService _models = ModelService();
  bool _loading = true;
  String? _error;
  int _modelCount = 0;
  int _fileCount = 0;
  bool _hasModel = false;
  String _modelName = '';

  bool get _ar => Localizations.localeOf(context).languageCode == 'ar';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      await _models.refreshModels();
      final files = await _models.listWorkspaceFiles();
      if (!mounted) return;
      setState(() {
        _modelCount = _models.getModels().length;
        _fileCount = files.length;
        _hasModel = _models.hasActiveModel();
        _modelName = _models.getActiveModelName();
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _modelCount = _models.getModels().length;
        _hasModel = _models.hasActiveModel();
        _modelName = _models.getActiveModelName();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_ar ? 'لوحة التحكم' : 'Dashboard',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: _ar ? 'مساحة العمل' : 'Workspace',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AgentWorkspaceScreen(steps: [])),
            ),
            icon: const Icon(Icons.folder_open_rounded),
          ),
          IconButton(
            tooltip: _ar ? 'الإعدادات' : 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _HeroPanel(
              title: _ar ? 'مساحة عمل الوكيل الذكي' : 'Your agent workspace',
              subtitle: _ar
                  ? 'إدارة النموذج المحلي والأدوات ومساحة العمل من مكان واحد.'
                  : 'Monitor your local model, tools and workspace in one place.',
              trailing: const Icon(Icons.auto_awesome_rounded, size: 34, color: Colors.white),
            ),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(child: _MetricCard(
                icon: Icons.memory_rounded,
                label: _ar ? 'النموذج النشط' : 'Active model',
                value: _loading ? '—' : (_hasModel ? (_ar ? 'نشط' : 'Ready') : (_ar ? 'غير محمّل' : 'Not loaded')),
                detail: _hasModel ? _modelName : (_ar ? 'اختر نموذج GGUF' : 'Choose a GGUF model'),
                tint: _hasModel ? AppTheme.primary : AppTheme.warning,
              )),
              const SizedBox(width: 10),
              Expanded(child: _MetricCard(
                icon: Icons.inventory_2_outlined,
                label: _ar ? 'النماذج المتاحة' : 'Available models',
                value: _loading ? '—' : '$_modelCount',
                detail: _ar ? 'مكتشفة على الجهاز' : 'Discovered on device',
                tint: AppTheme.secondary,
              )),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _MetricCard(
                icon: Icons.folder_copy_outlined,
                label: _ar ? 'ملفات مساحة العمل' : 'Workspace files',
                value: _loading ? '—' : '$_fileCount',
                detail: _ar ? 'ملفات محلية' : 'Local files',
                tint: AppTheme.primaryLight,
              )),
              const SizedBox(width: 10),
              Expanded(child: _MetricCard(
                icon: Icons.terminal_rounded,
                label: _ar ? 'أدوات التنفيذ' : 'Execution tools',
                value: '4',
                detail: _ar ? 'ملفات وPython' : 'Files & Python',
                tint: AppTheme.secondary,
              )),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _Notice(
                icon: Icons.info_outline_rounded,
                text: _ar
                    ? 'تعذر تحديث بعض بيانات الجهاز: $_error'
                    : 'Some device data could not be refreshed: $_error',
              ),
            ],
            const SizedBox(height: 22),
            _SectionTitle(_ar ? 'الوصول السريع' : 'Quick access'),
            const SizedBox(height: 10),
            _ActionTile(
              icon: Icons.forum_outlined,
              title: _ar ? 'ابدأ محادثة مع الوكيل' : 'Chat with your agent',
              subtitle: _ar ? 'إرسال المهام ومتابعة التنفيذ' : 'Send tasks and follow execution',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ChatScreen()),
              ),
            ),
            _ActionTile(
              icon: Icons.folder_open_outlined,
              title: _ar ? 'مساحة العمل والملفات' : 'Workspace & files',
              subtitle: _ar ? 'تحرير الملفات ومعاينة HTML' : 'Edit files and preview HTML',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AgentWorkspaceScreen(steps: [])),
              ),
            ),
            _ActionTile(
              icon: Icons.tune_rounded,
              title: _ar ? 'إعدادات التشغيل والمظهر' : 'Runtime & appearance settings',
              subtitle: _ar ? 'اللغة والثيم وإعدادات التشغيل المتاحة' : 'Language, theme and available runtime settings',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _ar
                  ? 'الأرقام المعروضة تُقرأ من النموذج ومساحة العمل الفعليين؛ لا تمثل إحصاءات استخدام افتراضية.'
                  : 'Metrics are read from the actual model catalog and workspace; no synthetic usage statistics are shown.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(.55)),
            ),
          ],
        ),
      ),
    );
  }
}

class AgentWorkflowPage extends StatelessWidget {
  const AgentWorkflowPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return Scaffold(
      appBar: AppBar(title: Text(ar ? 'مخطط سير العمل' : 'Workflow builder')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Notice(
            icon: Icons.info_outline_rounded,
            text: ar
                ? 'هذه معاينة بصرية لبنية سير العمل. محرّك تنفيذ المخططات وربط الشروط غير موصول بعد؛ لا يتم تشغيل هذه العقد.'
                : 'This is a visual workflow layout. A workflow execution engine and condition binding are not connected yet; these nodes do not run.',
          ),
          const SizedBox(height: 18),
          _WorkflowNode(
            number: '01',
            icon: Icons.input_rounded,
            title: ar ? 'استقبال المهمة' : 'Receive task',
            subtitle: ar ? 'رسالة المستخدم' : 'User prompt',
            color: AppTheme.secondary,
          ),
          const _FlowConnector(),
          _WorkflowNode(
            number: '02',
            icon: Icons.psychology_alt_rounded,
            title: ar ? 'تحليل وتخطيط' : 'Analyze & plan',
            subtitle: ar ? 'تحديد المطلوب والخطوات' : 'Identify intent and steps',
            color: AppTheme.primary,
          ),
          const _FlowConnector(label: 'IF / CONDITION'),
          _WorkflowNode(
            number: '03',
            icon: Icons.rule_rounded,
            title: ar ? 'فحص شرط التنفيذ' : 'Evaluate condition',
            subtitle: ar ? 'هل تتطلب المهمة أداة؟' : 'Does the task require a tool?',
            color: AppTheme.warning,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _BranchCard(
                label: 'TRUE',
                color: AppTheme.primary,
                title: ar ? 'تنفيذ الأداة' : 'Run tool',
                subtitle: ar ? 'ملف أو Python' : 'File or Python',
              )),
              const SizedBox(width: 12),
              Expanded(child: _BranchCard(
                label: 'FALSE',
                color: AppTheme.secondary,
                title: ar ? 'إجابة مباشرة' : 'Direct response',
                subtitle: ar ? 'صياغة الرد' : 'Compose response',
              )),
            ],
          ),
          const _FlowConnector(),
          _WorkflowNode(
            number: '04',
            icon: Icons.fact_check_outlined,
            title: ar ? 'التحقق من النتيجة' : 'Verify result',
            subtitle: ar ? 'عدم ادعاء نجاح دون نتيجة' : 'Never claim success without a result',
            color: AppTheme.primary,
          ),
          const _FlowConnector(),
          _WorkflowNode(
            number: '05',
            icon: Icons.chat_bubble_outline_rounded,
            title: ar ? 'إرجاع الرد' : 'Return response',
            subtitle: ar ? 'عرض النتيجة للمستخدم' : 'Present result to the user',
            color: AppTheme.secondary,
          ),
        ],
      ),
    );
  }
}

class AgentStatusPage extends StatefulWidget {
  const AgentStatusPage({super.key});

  @override
  State<AgentStatusPage> createState() => _AgentStatusPageState();
}

class _AgentStatusPageState extends State<AgentStatusPage> {
  final ModelService _service = ModelService();
  bool _loading = true;
  String? _error;

  bool get _ar => Localizations.localeOf(context).languageCode == 'ar';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await _service.refreshModels();
      if (mounted) setState(() { _loading = false; _error = null; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _service.hasActiveModel();
    final model = _service.getActiveModelName();
    return Scaffold(
      appBar: AppBar(
        title: Text(_ar ? 'حالة الوكيل' : 'Agent status'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HeroPanel(
            title: _loading
                ? (_ar ? 'جارٍ فحص المحرك' : 'Checking runtime')
                : active
                    ? (_ar ? 'المحرك المحلي جاهز' : 'Local runtime ready')
                    : (_ar ? 'لا يوجد نموذج نشط' : 'No active model'),
            subtitle: _loading
                ? (_ar ? 'يتم الاستعلام عن حالة النموذج.' : 'Reading the model runtime state.')
                : active
                    ? model
                    : (_ar ? 'استورد نموذج GGUF وحمّله من شاشة النماذج.' : 'Import and load a GGUF model from model settings.'),
            trailing: Icon(
              active ? Icons.check_circle_rounded : Icons.pause_circle_outline_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
          const SizedBox(height: 18),
          _SectionTitle(_ar ? 'مكوّنات التشغيل' : 'Runtime components'),
          const SizedBox(height: 10),
          _StatusRow(
            title: _ar ? 'محرك GGUF المحلي' : 'Local GGUF runtime',
            subtitle: active ? model : (_ar ? 'لا يوجد نموذج محمّل' : 'No model loaded'),
            status: _loading ? 'checking' : active ? 'ready' : 'inactive',
            ar: _ar,
          ),
          _StatusRow(
            title: _ar ? 'أدوات الملفات' : 'Workspace file tools',
            subtitle: _ar ? 'إنشاء وقراءة وتحديث الملفات' : 'Create, read and update files',
            status: 'ready',
            ar: _ar,
          ),
          _StatusRow(
            title: 'Python',
            subtitle: _ar ? 'تنفيذ محلي مقيّد عبر الجسر الأصلي' : 'Sandboxed local execution via native bridge',
            status: 'ready',
            ar: _ar,
          ),
          _StatusRow(
            title: _ar ? 'الاستدلال في الخلفية' : 'Background inference',
            subtitle: _ar ? 'يتطلب خدمة Android أمامية مستقلة' : 'Requires a dedicated Android foreground service',
            status: 'limited',
            ar: _ar,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _Notice(icon: Icons.warning_amber_rounded, text: _error!),
          ],
          const SizedBox(height: 12),
          Text(
            _ar
                ? 'تعكس الحالة ما يمكن التحقق منه من واجهات التطبيق الحالية، ولا تعتبر وجود خدمة أو أداة دليلاً على اختبارها على كل الأجهزة.'
                : 'Status reflects capabilities exposed by the current app code; the presence of a service or tool is not proof of device-wide testing.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class AgentIntegrationsPage extends StatefulWidget {
  const AgentIntegrationsPage({super.key});

  @override
  State<AgentIntegrationsPage> createState() => _AgentIntegrationsPageState();
}

class _AgentIntegrationsPageState extends State<AgentIntegrationsPage> {
  final ModelService _service = ModelService();
  bool _loading = true;
  bool _modelReady = false;
  int _models = 0;
  String? _error;
  bool get _ar => Localizations.localeOf(context).languageCode == 'ar';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      await _service.refreshModels();
      if (mounted) setState(() {
        _modelReady = _service.hasActiveModel();
        _models = _service.getModels().length;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_ar ? 'التكاملات والاتصالات' : 'Integrations'),
        actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _ar ? 'مصادر التشغيل والأدوات المتاحة' : 'Runtime providers & tools',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          _IntegrationTile(
            icon: Icons.memory_rounded,
            title: _ar ? 'نماذج GGUF المحلية' : 'Local GGUF models',
            subtitle: _loading
                ? (_ar ? 'جارٍ الفحص...' : 'Checking...')
                : _ar ? '$_models نموذج مكتشف' : '$_models model(s) discovered',
            badge: _loading ? 'checking' : _modelReady ? 'connected' : 'not_connected',
            ar: _ar,
          ),
          _IntegrationTile(
            icon: Icons.folder_copy_outlined,
            title: _ar ? 'مساحة العمل المحلية' : 'Local workspace',
            subtitle: _ar ? 'عمليات الملفات عبر القناة الأصلية' : 'File operations through the native channel',
            badge: 'available',
            ar: _ar,
          ),
          _IntegrationTile(
            icon: Icons.terminal_rounded,
            title: 'Python Runtime',
            subtitle: _ar ? 'منفّذ محلي مقيّد' : 'Sandboxed local executor',
            badge: 'available',
            ar: _ar,
          ),
          _IntegrationTile(
            icon: Icons.cloud_outlined,
            title: 'OpenRouter',
            subtitle: _ar
                ? 'مزود سحابي غير موصول حالياً بمحرك التشغيل في هذا الفرع.'
                : 'Cloud provider is not currently wired into the runtime on this branch.',
            badge: 'not_configured',
            ar: _ar,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _Notice(icon: Icons.info_outline_rounded, text: _error!),
          ],
          const SizedBox(height: 14),
          _Notice(
            icon: Icons.lock_outline_rounded,
            text: _ar
                ? 'لا توجد هنا حقول API شكلية أو مفاتيح تُحفظ دون اتصال فعلي. ستظهر خيارات الربط فقط بعد تنفيذ مسار المصادقة والطلب والتحقق منه.'
                : 'No decorative API-key fields are shown. Provider controls will appear only after authentication, request handling and verification are implemented.',
          ),
        ],
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.title, required this.subtitle, required this.trailing});
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: AppTheme.primaryGradient,
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(color: AppTheme.primary.withOpacity(.18), blurRadius: 20, offset: const Offset(0, 9)),
      ],
    ),
    child: Row(children: [
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(.86), height: 1.4)),
        ],
      )),
      const SizedBox(width: 12),
      Container(
        width: 58, height: 58,
        decoration: BoxDecoration(color: Colors.white.withOpacity(.16), borderRadius: BorderRadius.circular(18)),
        child: Center(child: trailing),
      ),
    ]),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.icon, required this.label, required this.value, required this.detail, required this.tint});
  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final Color tint;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface.withOpacity(.92),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: tint.withOpacity(.2)),
      boxShadow: [BoxShadow(color: tint.withOpacity(.06), blurRadius: 16, offset: const Offset(0, 5))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: tint, size: 22),
      const SizedBox(height: 12),
      Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 3),
      Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withOpacity(.55), fontSize: 10)),
    ]),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Text(title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800));
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 9),
    child: ListTile(
      leading: Container(width: 42, height: 42,
        decoration: BoxDecoration(color: AppTheme.primary.withOpacity(.1), borderRadius: BorderRadius.circular(13)),
        child: Icon(icon, color: AppTheme.primary)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: AppTheme.secondary.withOpacity(.07),
      border: Border.all(color: AppTheme.secondary.withOpacity(.16)),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 19, color: AppTheme.secondary),
      const SizedBox(width: 9),
      Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.45))),
    ]),
  );
}

class _WorkflowNode extends StatelessWidget {
  const _WorkflowNode({required this.number, required this.icon, required this.title, required this.subtitle, required this.color});
  final String number;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: color.withOpacity(.35)),
      boxShadow: [BoxShadow(color: color.withOpacity(.06), blurRadius: 14, offset: const Offset(0, 4))],
    ),
    child: Row(children: [
      Container(width: 38, height: 38,
        decoration: BoxDecoration(color: color.withOpacity(.12), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: color)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ])),
      Text(number, style: TextStyle(color: color.withOpacity(.8), fontWeight: FontWeight.w800)),
    ]),
  );
}

class _FlowConnector extends StatelessWidget {
  const _FlowConnector({this.label});
  final String? label;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: label == null ? 30 : 44,
    child: Column(children: [
      Expanded(child: Container(width: 2, color: AppTheme.primary.withOpacity(.35))),
      Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppTheme.primary),
      if (label != null) Text(label!, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppTheme.primary)),
    ]),
  );
}

class _BranchCard extends StatelessWidget {
  const _BranchCard({required this.label, required this.color, required this.title, required this.subtitle});
  final String label;
  final Color color;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.withOpacity(.38)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
    ]),
  );
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.title, required this.subtitle, required this.status, required this.ar});
  final String title;
  final String subtitle;
  final String status;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final ready = status == 'ready';
    final color = ready ? AppTheme.primary : status == 'limited' ? AppTheme.warning : AppTheme.secondary;
    final label = status == 'checking'
        ? (ar ? 'يفحص' : 'Checking')
        : status == 'ready'
            ? (ar ? 'جاهز' : 'Ready')
            : status == 'limited'
                ? (ar ? 'محدود' : 'Limited')
                : (ar ? 'غير نشط' : 'Inactive');
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        leading: Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _IntegrationTile extends StatelessWidget {
  const _IntegrationTile({required this.icon, required this.title, required this.subtitle, required this.badge, required this.ar});
  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;
  final bool ar;
  @override
  Widget build(BuildContext context) {
    final connected = badge == 'connected' || badge == 'available';
    final color = connected ? AppTheme.primary : badge == 'checking' ? AppTheme.secondary : AppTheme.warning;
    final label = badge == 'connected'
        ? (ar ? 'متصل' : 'Connected')
        : badge == 'available'
            ? (ar ? 'متاح' : 'Available')
            : badge == 'checking'
                ? (ar ? 'يفحص' : 'Checking')
                : (ar ? 'غير مهيأ' : 'Not configured');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        leading: Container(width: 44, height: 44,
          decoration: BoxDecoration(color: color.withOpacity(.1), borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: color)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle)),
        trailing: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
      ),
    );
  }
}
