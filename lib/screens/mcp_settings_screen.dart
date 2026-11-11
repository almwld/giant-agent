import 'package:flutter/material.dart';

import '../domain/mcp/mcp_client.dart';
import '../services/agent_service.dart';

class McpSettingsScreen extends StatefulWidget {
  const McpSettingsScreen({super.key});

  @override
  State<McpSettingsScreen> createState() => _McpSettingsScreenState();
}

class _McpSettingsScreenState extends State<McpSettingsScreen> {
  final AgentService _agent = AgentService.instance;
  List<McpServerConfig> _servers = const <McpServerConfig>[];
  final Map<String, List<McpRemoteTool>> _tools = <String, List<McpRemoteTool>>{};
  final Map<String, List<Map<String, dynamic>>> _resources =
      <String, List<Map<String, dynamic>>>{};
  final Set<String> _loading = <String>{};
  bool _initialLoading = true;

  bool get _arabic => Localizations.localeOf(context).languageCode == 'ar';
  String tr(String ar, String en) => _arabic ? ar : en;

  @override
  void initState() {
    super.initState();
    _loadServers();
  }

  Future<void> _loadServers() async {
    try {
      final servers = await _agent.mcpServers();
      if (!mounted) return;
      setState(() {
        _servers = servers;
        _initialLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _initialLoading = false);
      _message(error.toString(), isError: true);
    }
  }

  void _message(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _addServer() async {
    final id = TextEditingController();
    final name = TextEditingController();
    final endpoint = TextEditingController();
    final token = TextEditingController();
    try {
      final values = await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(tr('إضافة خادم MCP', 'Add MCP server')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: id, textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: tr('المعرّف (إنجليزي)', 'Server ID (ASCII)'))),
                TextField(controller: name, textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: tr('اسم الخادم', 'Server name'))),
                TextField(controller: endpoint, keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: tr('رابط MCP عبر HTTPS', 'MCP HTTPS endpoint'))),
                TextField(controller: token, obscureText: true,
                  decoration: InputDecoration(
                    labelText: tr('Bearer token (اختياري)', 'Bearer token (optional)'),
                    helperText: tr('يُحفظ في التخزين الآمن.', 'Stored in secure storage.'),
                  )),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
              child: Text(tr('إلغاء', 'Cancel'))),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, {
                'id': id.text.trim(),
                'name': name.text.trim(),
                'endpoint': endpoint.text.trim(),
                'token': token.text.trim(),
              }),
              child: Text(tr('حفظ', 'Save')),
            ),
          ],
        ),
      );
      if (values == null) return;
      await _agent.addMcpServer(
        id: values['id']!,
        name: values['name']!,
        endpoint: values['endpoint']!,
        bearerToken: values['token'],
      );
      await _loadServers();
      _message(tr('تم حفظ إعداد الخادم. اكتشف أدواته للتحقق من الاتصال.', 'Server saved. Discover its tools to verify the connection.'));
    } catch (error) {
      _message(error.toString(), isError: true);
    } finally {
      id.dispose();
      name.dispose();
      endpoint.dispose();
      token.dispose();
    }
  }

  Future<void> _discover(McpServerConfig server) async {
    if (_loading.contains(server.id)) return;
    setState(() => _loading.add(server.id));
    try {
      final tools = await _agent.refreshMcpTools(server.id);
      List<Map<String, dynamic>> resources = const <Map<String, dynamic>>[];
      try {
        resources = await McpClient.instance.listResources(server.id);
      } catch (_) {
        // A server may expose tools without supporting the optional resources capability.
      }
      if (!mounted) return;
      setState(() {
        _tools[server.id] = tools;
        _resources[server.id] = resources;
      });
      _message(tr('تم اكتشاف ${tools.length} أداة و${resources.length} مورداً.',
        'Discovered ${tools.length} tools and ${resources.length} resources.'));
    } catch (error) {
      _message(error.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _loading.remove(server.id));
    }
  }

  Future<void> _remove(McpServerConfig server) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('إزالة خادم MCP', 'Remove MCP server')),
        content: Text(tr('ستُحذف إعدادات الاتصال ورمز الوصول المحفوظ لهذا الخادم.',
          'The server connection settings and saved access token will be deleted.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr('إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr('إزالة', 'Remove'))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _agent.removeMcpServer(server.id);
      if (!mounted) return;
      setState(() {
        _tools.remove(server.id);
        _resources.remove(server.id);
      });
      await _loadServers();
    } catch (error) {
      _message(error.toString(), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('خوادم MCP', 'MCP servers'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addServer,
        icon: const Icon(Icons.add_link),
        label: Text(tr('إضافة خادم', 'Add server')),
      ),
      body: _initialLoading
          ? const Center(child: CircularProgressIndicator())
          : _servers.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      tr('لا توجد خوادم MCP بعد. أضف عنوان Streamable HTTP ورمز الوصول الاختياري.',
                        'No MCP servers yet. Add a Streamable HTTP endpoint and an optional access token.'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(tr(
                          'تُقبل روابط HTTPS فقط (يسمح بـ HTTP على localhost للاختبار). الأدوات التي لا تعلن readOnlyHint=true تحتاج موافقة صريحة قبل التنفيذ.',
                          'HTTPS only (HTTP is allowed for localhost testing). Tools without readOnlyHint=true require explicit approval before execution.',
                        )),
                      ),
                    ),
                    for (final server in _servers) _serverCard(server),
                  ],
                ),
    );
  }

  Widget _serverCard(McpServerConfig server) {
    final tools = _tools[server.id];
    final resources = _resources[server.id];
    final busy = _loading.contains(server.id);
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.hub_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(server.name, style: Theme.of(context).textTheme.titleMedium),
                      Text(server.id, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: tr('إزالة', 'Remove'),
                  onPressed: busy ? null : () => _remove(server),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            SelectableText(server.endpoint, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              server.bearerToken?.isNotEmpty == true
                  ? tr('رمز وصول محفوظ بأمان', 'Access token stored securely')
                  : tr('لا يوجد رمز وصول', 'No access token'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: busy ? null : () => _discover(server),
              icon: busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync),
              label: Text(tr('اكتشاف الأدوات والموارد', 'Discover tools & resources')),
            ),
            if (tools != null) ...[
              const Divider(),
              Text(tr('الأدوات (${tools.length})', 'Tools (${tools.length})'),
                style: Theme.of(context).textTheme.titleSmall),
              for (final tool in tools)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    (tool.annotations['readOnlyHint'] == true &&
                        tool.annotations['destructiveHint'] != true &&
                        tool.annotations['openWorldHint'] != true)
                        ? Icons.visibility_outlined
                        : Icons.verified_user_outlined,
                  ),
                  title: Text(tool.name),
                  subtitle: Text(tool.description.isEmpty
                      ? ((tool.annotations['readOnlyHint'] == true &&
                          tool.annotations['destructiveHint'] != true &&
                          tool.annotations['openWorldHint'] != true)
                          ? tr('قراءة فقط (حسب تلميحات الخادم)', 'Read only (server hint)')
                          : tr('تتطلب موافقة', 'Approval required'))
                      : tool.description),
                ),
              if (resources != null) ...[
                const Divider(),
                Text(tr('الموارد (${resources.length})', 'Resources (${resources.length})'),
                  style: Theme.of(context).textTheme.titleSmall),
                for (final resource in resources.take(30))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.insert_drive_file_outlined),
                    title: Text(resource['name']?.toString() ?? resource['uri']?.toString() ?? 'Resource'),
                    subtitle: Text(resource['uri']?.toString() ?? ''),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
