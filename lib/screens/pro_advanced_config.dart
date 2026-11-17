import 'package:flutter/material.dart';
import 'pro_feature_directory.dart';

import '../services/app_preferences.dart';
import '../services/model_provider_settings.dart';
import '../services/openrouter_model_catalog.dart';
import '../services/providers/kilo_gateway_provider.dart';
import '../services/openai_compatible_provider.dart';
import '../services/pro_control_center.dart';
import '../theme/pro_theme.dart';
import '../widgets/pro_app_bar.dart';
import 'mcp_settings_screen.dart';

class ProAdvancedConfig extends StatefulWidget {
  const ProAdvancedConfig({super.key});
  @override
  State<ProAdvancedConfig> createState() => _ProAdvancedConfigState();
}

class _ProAdvancedConfigState extends State<ProAdvancedConfig> {
  final _prefs = AppPreferences.instance;
  final _control = ProControlCenter.instance;
  ModelProviderMode? _mode;
  bool _busy = true;
  bool _hasStoredApiKey = false;
  bool _testingModel = false;
  final _key = TextEditingController();
  final _model = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final mode = await ModelProviderSettings.instance.getMode();
      final model = await KiloGatewayProvider.instance.getModel();
      final savedApiKey = await OpenAICompatibleProvider.instance.getApiKey();
      if (!mounted) return;
      setState(() {
        _mode = mode;
        _model.text = model;
        _hasStoredApiKey = savedApiKey?.trim().isNotEmpty == true;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
    try {
      await _control.initialize();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Runtime status unavailable: $error')),
      );
    }
  }

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _saveProvider() async {
    try {
      if (_mode == ModelProviderMode.openRouter) {
        // An empty field means "keep the securely stored key", not replace it.
        // Only a newly entered key is passed to configure when one is supplied.
        final enteredKey = _key.text.trim();
        final savedKey = await OpenAICompatibleProvider.instance.getApiKey();
        final apiKey = enteredKey.isNotEmpty ? enteredKey : (savedKey ?? '');
        await OpenAICompatibleProvider.instance.configure(
          apiKey: apiKey,
          model: _model.text,
        );
        await ModelProviderSettings.instance.setMode(ModelProviderMode.openRouter);
        if (enteredKey.isNotEmpty && mounted) {
          setState(() => _hasStoredApiKey = true);
          _key.clear();
        }
      } else {
        if (_mode == ModelProviderMode.zeroConfig) {
          await KiloGatewayProvider.instance.setModel(
            _model.text.isEmpty ? KiloGatewayProvider.defaultModel : _model.text,
          );
        }
        await ModelProviderSettings.instance.setMode(
          _mode ?? ModelProviderMode.local,
        );
      }
      await _control.refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Configuration saved securely.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _testSelectedModel() async {
    if (_mode != ModelProviderMode.openRouter || _testingModel) return;
    setState(() => _testingModel = true);
    try {
      final enteredKey = _key.text.trim();
      final savedKey = await OpenAICompatibleProvider.instance.getApiKey();
      await OpenAICompatibleProvider.instance.configure(
        apiKey: enteredKey.isNotEmpty ? enteredKey : (savedKey ?? ''),
        model: _model.text,
      );
      await ModelProviderSettings.instance.setMode(ModelProviderMode.openRouter);
      final answer = await OpenAICompatibleProvider.instance.generateStreaming(
        'Reply with exactly: OK',
        maxTokens: 32,
        temperature: 0,
      );
      if (mounted) {
        setState(() { _hasStoredApiKey = true; _key.clear(); });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Model connection successful: ${answer.trim()}')),
        );
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Model connection failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _testingModel = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _control,
      builder: (context, _) => Scaffold(
        backgroundColor: ProTheme.bgDark,
        appBar: ProAppBar(title: 'Advanced Configuration', onToolsPressed: () => openProFeatureDirectory(context)),
        body: Container(
          decoration: const BoxDecoration(gradient: ProTheme.bgGradient),
          child: _busy
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _card('Shared runtime status', Column(children: [
                      _statusLine('Requests', _control.metrics?.requestCount.toString() ?? '—'),
                      _statusLine('Persisted tasks', _control.tasks.length.toString()),
                      _statusLine('Subagents', _control.agents.length.toString()),
                      _statusLine('MCP servers', _control.integrations.length.toString()),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton.icon(
                          onPressed: () => _control.refresh(),
                          icon: const Icon(Icons.sync),
                          label: const Text('Synchronize runtime'),
                        ),
                      ),
                    ])),
                    const SizedBox(height: 14),
                    _card('Appearance & language', Column(children: [
                      DropdownButtonFormField<ThemeMode>(
                        value: _prefs.themeMode,
                        dropdownColor: ProTheme.bgCard,
                        decoration: const InputDecoration(labelText: 'Theme'),
                        items: ThemeMode.values.map((value) => DropdownMenuItem(value: value, child: Text(value.name))).toList(),
                        onChanged: (value) { if (value != null) _prefs.setThemeMode(value); },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _prefs.locale.languageCode,
                        dropdownColor: ProTheme.bgCard,
                        decoration: const InputDecoration(labelText: 'Language'),
                        items: const [
                          DropdownMenuItem(value: 'ar', child: Text('العربية')),
                          DropdownMenuItem(value: 'en', child: Text('English')),
                        ],
                        onChanged: (value) { if (value != null) _prefs.setLocale(Locale(value)); },
                      ),
                    ])),
                    const SizedBox(height: 14),
                    _card('Model runtime', Column(children: [
                      RadioListTile<ModelProviderMode>(
                        value: ModelProviderMode.local,
                        groupValue: _mode,
                        title: const Text('Local GGUF'),
                        onChanged: (value) => setState(() => _mode = value),
                      ),
                      RadioListTile<ModelProviderMode>(
                        value: ModelProviderMode.openRouter,
                        groupValue: _mode,
                        title: const Text('OpenRouter'),
                        onChanged: (value) => setState(() => _mode = value),
                      ),
                      RadioListTile<ModelProviderMode>(
                        value: ModelProviderMode.zeroConfig,
                        groupValue: _mode,
                        title: const Text('Kilo Gateway · Anonymous Free'),
                        subtitle: const Text('Free inference without account, API key, or Authorization header.'),
                        onChanged: (value) => setState(() => _mode = value),
                      ),
                      if (_mode == ModelProviderMode.zeroConfig)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Text(
                            'Anonymous free inference. Limit: 200 requests/hour/IP. Avoid confidential prompts; upstream providers may log data.',
                            style: TextStyle(color: ProTheme.textSecondary, fontSize: 12),
                          ),
                        ),
                      if (_mode == ModelProviderMode.zeroConfig) ...[
                        DropdownButtonFormField<String>(
                          value: KiloGatewayProvider.models.any((item) => item.id == _model.text)
                              ? _model.text : KiloGatewayProvider.defaultModel,
                          isExpanded: true,
                          dropdownColor: ProTheme.bgCard,
                          decoration: const InputDecoration(labelText: 'Anonymous free models'),
                          items: KiloGatewayProvider.models.map((item) =>
                            DropdownMenuItem<String>(
                              value: item.id,
                              child: Text('${item.name} · ${item.contextWindow}', overflow: TextOverflow.ellipsis),
                            ),
                          ).toList(),
                          onChanged: (value) { if (value != null) setState(() => _model.text = value); },
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: OutlinedButton.icon(
                            onPressed: _testingModel ? null : () async {
                              setState(() => _testingModel = true);
                              try {
                                await KiloGatewayProvider.instance.setModel(
                                  _model.text.isEmpty ? KiloGatewayProvider.defaultModel : _model.text,
                                );
                                final answer = await KiloGatewayProvider.instance.testConnection();
                                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Anonymous model responded: $answer')),
                                );
                              } catch (error) {
                                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Connection failed: $error')),
                                );
                              } finally {
                                if (mounted) setState(() => _testingModel = false);
                              }
                            },
                            icon: _testingModel
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.network_check),
                            label: Text(_testingModel ? 'Testing…' : 'Test selected model'),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Kilo anonymous free tier: 200 requests/hour/IP. Availability and model eligibility can change. Do not send confidential data.',
                            style: TextStyle(color: ProTheme.textSecondary, fontSize: 12),
                          ),
                        ),
                      ],
                      if (_mode == ModelProviderMode.openRouter) ...[
                        TextField(
                          controller: _key,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'OpenRouter API key',
                            helperText: _hasStoredApiKey
                                ? 'A key is already stored securely. Leave blank to keep it, or enter a replacement.'
                                : 'Stored securely after saving.',
                          ),
                        ),
                        DropdownButtonFormField<String>(
                          value: OpenRouterModelCatalog.find(_model.text)?.id,
                          isExpanded: true,
                          dropdownColor: ProTheme.bgCard,
                          decoration: const InputDecoration(labelText: 'Verified free models'),
                          hint: const Text('Choose a model'),
                          items: OpenRouterModelCatalog.options.map((option) =>
                            DropdownMenuItem<String>(
                              value: option.id,
                              child: Text('${option.name} · ${option.contextWindow}', overflow: TextOverflow.ellipsis),
                            ),
                          ).toList(),
                          onChanged: (value) { if (value != null) setState(() => _model.text = value); },
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _model,
                          decoration: const InputDecoration(
                            labelText: 'Model ID (manual override)',
                            helperText: 'The selected ID is sent to OpenRouter for each generation request.',
                          ),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: OutlinedButton.icon(
                            onPressed: _testingModel ? null : _testSelectedModel,
                            icon: _testingModel
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.network_check),
                            label: Text(_testingModel ? 'Testing model…' : 'Test selected model'),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Free endpoints are rate-limited and may be temporarily unavailable. Dots3-Note Preview is listed to expire on 2026-12-31.',
                            style: TextStyle(color: ProTheme.textSecondary, fontSize: 12),
                          ),
                        ),
                      ],
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: FilledButton(onPressed: _saveProvider, child: const Text('Save provider settings')),
                      ),
                    ])),
                    const SizedBox(height: 14),
                    _card('Integrations', ListTile(
                      title: const Text('Manage MCP servers'),
                      subtitle: const Text('Endpoints, secure tokens and tool discovery'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const McpSettingsScreen()));
                        await _control.refresh();
                      },
                    )),
                    const Padding(
                      padding: EdgeInsets.only(top: 14),
                      child: Text('Only settings backed by an existing runtime service are exposed. Unsupported crawler rates, expiry rules and social API credentials are omitted.', style: TextStyle(color: ProTheme.textSecondary, fontSize: 12, height: 1.4)),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _statusLine(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(color: ProTheme.textSecondary))),
      Text(value, style: const TextStyle(color: ProTheme.textPrimary, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _card(String title, Widget child) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: ProTheme.cardGradient,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: ProTheme.neonGreen.withOpacity(.15)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(color: ProTheme.neonGreen, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      child,
    ]),
  );
}
