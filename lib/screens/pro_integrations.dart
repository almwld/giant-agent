import 'package:flutter/material.dart';
import '../services/agent_service.dart';
import '../domain/mcp/mcp_client.dart';
import '../theme/pro_theme.dart';
import '../widgets/pro_app_bar.dart';
import 'mcp_settings_screen.dart';

class ProIntegrations extends StatefulWidget {
  const ProIntegrations({super.key});
  @override
  State<ProIntegrations> createState() => _ProIntegrationsState();
}

class _ProIntegrationsState extends State<ProIntegrations> {
  late Future<List<McpServerConfig>> _future;

  @override
  void initState() {
    super.initState();
    _future = AgentService.instance.mcpServers();
  }

  Future<void> _refresh() async {
    setState(() => _future = AgentService.instance.mcpServers());
    await _future;
  }

  Future<void> _openMcpSettings() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const McpSettingsScreen()));
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ProTheme.bgDark,
      appBar: ProAppBar(title: 'Integrations', showAddButton: true, onAddPressed: _openMcpSettings),
      body: Container(
        decoration: const BoxDecoration(gradient: ProTheme.bgGradient),
        child: FutureBuilder<List<McpServerConfig>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError) return Center(child: Text(snapshot.error.toString()));
            final servers = snapshot.data ?? [];
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(gradient: ProTheme.cardGradient, borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      const Icon(Icons.hub, color: ProTheme.neonGreen),
                      const SizedBox(width: 12),
                      Expanded(child: Text('${servers.length} MCP server configuration(s). Discover tools in server settings to verify connectivity.', style: const TextStyle(color: ProTheme.textSecondary, fontSize: 12))),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  if (servers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(30),
                      child: Text('No MCP integrations configured yet.', textAlign: TextAlign.center, style: TextStyle(color: ProTheme.textSecondary)),
                    ),
                  ...servers.map((server) => Card(
                    color: ProTheme.bgCard,
                    child: ListTile(
                      leading: const Icon(Icons.link, color: ProTheme.neonGreen),
                      title: Text(server.name, style: const TextStyle(color: ProTheme.textPrimary)),
                      subtitle: Text(server.endpoint, style: const TextStyle(color: ProTheme.textSecondary, fontSize: 11)),
                      trailing: const Icon(Icons.chevron_right, color: ProTheme.neonGreen),
                      onTap: _openMcpSettings,
                    ),
                  )),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
