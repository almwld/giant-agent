import 'package:flutter/material.dart';
import '../services/model_service.dart';

class ModelSelector extends StatefulWidget {
  final VoidCallback onModelChanged;
  const ModelSelector({super.key, required this.onModelChanged});
  @override
  State<ModelSelector> createState() => _ModelSelectorState();
}

class _ModelSelectorState extends State<ModelSelector> {
  final ModelService _service = ModelService();
  List<Map<String, dynamic>> _models = [];
  String? _activeModelId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  Future<void> _loadModels() async {
    await _service.refreshModels();
    if (!mounted) return;
    setState(() {
      _models = _service.getModels();
      _activeModelId = _service.getActiveModel()['id'] as String?;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selected = _models.any((model) => model['id'] == _activeModelId)
        ? _activeModelId
        : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        const Icon(Icons.model_training, size: 18, color: Colors.white70),
        const SizedBox(width: 8),
        const Text('النموذج:', style: TextStyle(fontSize: 12, color: Colors.white70)),
        const SizedBox(width: 8),
        Expanded(
          child: _loading
              ? const LinearProgressIndicator()
              : DropdownButton<String>(
                  value: selected,
                  hint: const Text('اختر نموذجاً', style: TextStyle(color: Colors.white70)),
                  dropdownColor: Colors.grey.shade800,
                  underline: const SizedBox.shrink(),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  isExpanded: true,
                  items: _models.map((model) => DropdownMenuItem<String>(
                    value: model['id'] as String,
                    child: Text('${model['name']} (${model['size']})'),
                  )).toList(),
                  onChanged: (value) async {
                    if (value == null) return;
                    final changed = await _service.switchModel(value);
                    if (!mounted) return;
                    if (changed) {
                      setState(() => _activeModelId = value);
                      widget.onModelChanged();
                    }
                  },
                ),
        ),
      ]),
    );
  }
}
