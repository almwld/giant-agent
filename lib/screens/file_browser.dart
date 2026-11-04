import 'package:flutter/material.dart';

import '../services/model_service.dart';

/// Model library screen backed by the app-private GGUF runtime.
/// Android storage permissions and public Downloads paths are deliberately
/// avoided; model import is handled by the native Storage Access Framework.
class FileBrowser extends StatefulWidget {
  const FileBrowser({super.key});

  @override
  State<FileBrowser> createState() => _FileBrowserState();
}

class _FileBrowserState extends State<FileBrowser> {
  final ModelService _models = ModelService();
  List<Map<String, dynamic>> _items = const [];
  Map<String, dynamic> _active = const {};
  bool _loading = true;
  bool _importing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      await _models.refreshModels();
      if (!mounted) return;
      setState(() {
        _items = _models.getModels();
        _active = _models.getActiveModel();
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _importModel() async {
    if (_importing) return;
    setState(() { _importing = true; _error = null; });
    try {
      final imported = await _models.importModelFromFile();
      if (!mounted) return;
      await _refresh();
      if (!mounted) return;
      if (imported) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم استيراد نموذج GGUF إلى مساحة التطبيق الخاصة')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لم يتم استيراد نموذج جديد')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _activate(Map<String, dynamic> model) async {
    final id = model['id']?.toString();
    if (id == null || id.isEmpty || _loading || _importing) return;
    setState(() { _loading = true; _error = null; });
    try {
      final loaded = await _models.switchModel(id);
      if (!mounted) return;
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loaded
            ? 'تم تفعيل النموذج: ${model['name']}'
            : 'تعذر تفعيل النموذج المحدد')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeName = _active['name']?.toString();
    return Scaffold(
      appBar: AppBar(
        title: const Text('مكتبة نماذج GGUF'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'تحديث النماذج',
            onPressed: _loading || _importing ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading && _items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (activeName != null && activeName.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.check_circle, color: Colors.green),
                    title: const Text('النموذج النشط'),
                    subtitle: Text(activeName),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                Expanded(
                  child: _items.isEmpty
                      ? const Center(
                          child: Text('لا توجد نماذج GGUF بعد. استورد نموذجًا للبدء.'),
                        )
                      : ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final model = _items[index];
                            final selected = model['id'] == _active['id'];
                            return ListTile(
                              leading: Icon(
                                selected ? Icons.check_circle : Icons.memory,
                                color: selected ? Colors.green : null,
                              ),
                              title: Text(model['name']?.toString() ?? 'GGUF model'),
                              subtitle: Text(
                                '${model['size'] ?? 'الحجم غير معروف'} • GGUF',
                              ),
                              trailing: selected
                                  ? const Text('نشط')
                                  : TextButton(
                                      onPressed: _loading || _importing
                                          ? null
                                          : () => _activate(model),
                                      child: const Text('تفعيل'),
                                    ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading || _importing ? null : _importModel,
        icon: _importing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: Text(_importing ? 'جارٍ الاستيراد...' : 'استيراد GGUF'),
      ),
    );
  }
}
