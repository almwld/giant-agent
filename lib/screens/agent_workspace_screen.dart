import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/model_service.dart';

/// Local workspace editor with an embedded HTML/JS preview.
/// It is not a remote desktop and does not compile or run Flutter projects.
class AgentWorkspaceScreen extends StatefulWidget {
  final List<Map<String, dynamic>> steps;
  const AgentWorkspaceScreen({super.key, required this.steps});

  static final ValueNotifier<String?> fileChanges = ValueNotifier<String?>(null);

  @override
  State<AgentWorkspaceScreen> createState() => _AgentWorkspaceScreenState();
}

class _AgentWorkspaceScreenState extends State<AgentWorkspaceScreen> {
  final ModelService _service = ModelService();
  final TextEditingController _editor = TextEditingController();
  late final WebViewController _webView;
  List<String> _files = [];
  String? _selectedPath;
  bool _loading = false;
  bool _saving = false;
  String? _error;
  int _previewVersion = 0;

  @override
  void initState() {
    super.initState();
    _webView = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0F1720))
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (error) {
          if (!mounted || error.isForMainFrame != true) return;
          setState(() => _error = error.description);
        },
      ));
    AgentWorkspaceScreen.fileChanges.addListener(_onFileChanged);
    _refreshFiles(selectPath: AgentWorkspaceScreen.fileChanges.value);
  }

  @override
  void dispose() {
    AgentWorkspaceScreen.fileChanges.removeListener(_onFileChanged);
    _editor.dispose();
    super.dispose();
  }

  void _onFileChanged() {
    final path = AgentWorkspaceScreen.fileChanges.value;
    if (path == null || path.isEmpty) return;
    _refreshFiles(selectPath: path);
  }

  Future<void> _refreshFiles({String? selectPath}) async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final files = await _service.listWorkspaceFiles();
      if (!mounted) return;
      setState(() => _files = files);
      final target = selectPath != null && files.contains(selectPath)
          ? selectPath
          : (_selectedPath != null && files.contains(_selectedPath)
              ? _selectedPath
              : (files.isNotEmpty ? files.first : null));
      if (target != null) await _openFile(target);
      else {
        _editor.clear();
        _selectedPath = null;
        await _showEmptyPreview();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openFile(String path) async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await _service.readFile(path: path);
      if (!mounted) return;
      _selectedPath = path;
      _editor.text = result['content']?.toString() ?? '';
      await _runPreview();
      setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _escapeHtml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  Future<void> _showEmptyPreview() async {
    await _webView.loadHtmlString('''
      <!doctype html><html><meta name="viewport" content="width=device-width, initial-scale=1">
      <body style="margin:0;background:#0f1720;color:#94a3b8;font:16px sans-serif;display:grid;place-items:center;height:100vh">
      <div style="text-align:center"><h2>Workspace Preview</h2><p>أنشئ ملف HTML لعرضه هنا.</p></div></body></html>
    ''');
  }

  Future<void> _runPreview() async {
    final path = _selectedPath;
    if (path == null) return;
    final extension = path.split('.').last.toLowerCase();
    if (extension == 'html' || extension == 'htm') {
      await _webView.loadHtmlString(_editor.text, baseUrl: 'https://preview.local/');
    } else {
      final code = _escapeHtml(_editor.text);
      final title = _escapeHtml(path);
      await _webView.loadHtmlString('''
        <!doctype html><html><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>body{margin:0;background:#0f1720;color:#e2e8f0;font:13px monospace;padding:18px}
        h3{color:#5eead4;font:600 15px sans-serif;overflow-wrap:anywhere}
        pre{white-space:pre-wrap;overflow-wrap:anywhere;line-height:1.55}</style>
        <h3>Code Preview — $title</h3>
        <p style="font:13px sans-serif;color:#fbbf24">هذا الملف ليس HTML؛ يتم عرض الكود فقط ولا يتم تشغيله داخل WebView.</p>
        <pre>$code</pre></html>
      ''');
    }
    if (mounted) setState(() => _previewVersion++);
  }

  Future<void> _saveAndRun() async {
    final path = _selectedPath;
    if (path == null || _saving) return;
    setState(() { _saving = true; _error = null; });
    try {
      await _service.writeFile(path: path, content: _editor.text);
      await _runPreview();
      await _refreshFiles(selectPath: path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ الملف وتحديث المعاينة')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHtml = _selectedPath != null &&
        const {'html', 'htm'}.contains(_selectedPath!.split('.').last.toLowerCase());
    return Scaffold(
      backgroundColor: const Color(0xFF0F1720),
      appBar: AppBar(
        backgroundColor: const Color(0xFF17212B),
        foregroundColor: Colors.white,
        title: const Text('معاينة مساحة العمل'),
        actions: [
          IconButton(
            tooltip: 'تحديث قائمة الملفات',
            onPressed: _loading ? null : _refreshFiles,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'حفظ وتشغيل',
            onPressed: _saving || _selectedPath == null ? null : _saveAndRun,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_arrow_rounded, color: Colors.tealAccent),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            height: 54,
            color: const Color(0xFF151F29),
            child: _files.isEmpty
                ? const Center(child: Text('لا توجد ملفات في مساحة العمل', style: TextStyle(color: Colors.white54)))
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    itemCount: _files.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 7),
                    itemBuilder: (context, index) {
                      final path = _files[index];
                      final selected = path == _selectedPath;
                      return ActionChip(
                        backgroundColor: selected ? Colors.teal.withOpacity(.25) : const Color(0xFF243342),
                        side: BorderSide(color: selected ? Colors.tealAccent : Colors.white12),
                        avatar: Icon(Icons.insert_drive_file_outlined, size: 16,
                            color: selected ? Colors.tealAccent : Colors.white60),
                        label: Text(path, style: TextStyle(fontSize: 11,
                            color: selected ? Colors.tealAccent : Colors.white70)),
                        onPressed: () => _openFile(path),
                      );
                    },
                  ),
          ),
          if (_error != null)
            MaterialBanner(
              backgroundColor: const Color(0xFF4A2025),
              content: Text(_error!, style: const TextStyle(color: Colors.white)),
              leading: const Icon(Icons.error_outline, color: Colors.redAccent),
              actions: [TextButton(onPressed: () => setState(() => _error = null), child: const Text('إغلاق'))],
            ),
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              final editor = Column(
                children: [
                  _sectionHeader('محرر الكود', Icons.code, _selectedPath ?? 'اختر ملفاً'),
                  Expanded(
                    child: TextField(
                      controller: _editor,
                      expands: true,
                      minLines: null,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      // Code is always edited left-to-right even while the
                      // surrounding workspace UI follows the Arabic locale.
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.left,
                      textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(color: Color(0xFFE2E8F0), fontFamily: 'monospace', fontSize: 12, height: 1.5),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(14),
                        hintText: 'اختر ملفاً لعرض محتواه وتعديله...',
                        hintStyle: TextStyle(color: Colors.white38),
                      ),
                    ),
                  ),
                  Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    color: const Color(0xFF17212B),
                    child: Row(children: [
                      const Expanded(child: Text('يُحفظ التعديل في مساحة العمل المحلية',
                          style: TextStyle(color: Colors.white54, fontSize: 10))),
                      TextButton.icon(
                        onPressed: _selectedPath == null || _saving ? null : _saveAndRun,
                        icon: const Icon(Icons.play_arrow, size: 17),
                        label: const Text('حفظ وتشغيل'),
                      ),
                    ]),
                  ),
                ],
              );
              final preview = Column(children: [
                _sectionHeader('المعاينة الحية', Icons.web, isHtml ? 'HTML / CSS / JS' : 'عرض الكود'),
                Expanded(child: WebViewWidget(controller: _webView)),
                Container(
                  height: 30,
                  color: const Color(0xFF17212B),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(children: [
                    Icon(Icons.circle, size: 7, color: isHtml ? Colors.greenAccent : Colors.orangeAccent),
                    const SizedBox(width: 7),
                    Text(isHtml ? 'WebView • Preview #$_previewVersion' : 'Code only • Flutter requires export/build',
                        style: const TextStyle(color: Colors.white54, fontSize: 10)),
                  ]),
                ),
              ]);
              if (constraints.maxWidth >= 700) {
                return Row(children: [
                  Expanded(child: editor),
                  const VerticalDivider(width: 1, color: Colors.white12),
                  Expanded(child: preview),
                ]);
              }
              return Column(children: [
                Expanded(flex: 5, child: editor),
                const Divider(height: 1, color: Colors.white12),
                Expanded(flex: 5, child: preview),
              ]);
            }),
          ),
          if (_loading)
            const LinearProgressIndicator(minHeight: 2, color: Colors.tealAccent, backgroundColor: Colors.transparent),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, String subtitle) {
    return Container(
      width: double.infinity,
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: const Color(0xFF1B2936),
      child: Row(children: [
        Icon(icon, color: Colors.tealAccent, size: 16),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        const Spacer(),
        Flexible(child: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 10))),
      ]),
    );
  }
}
