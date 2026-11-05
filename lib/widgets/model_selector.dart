import 'package:flutter/material.dart';
import '../services/model_service.dart';

class ModelSelector extends StatefulWidget {
  final VoidCallback onModelChanged;

  const ModelSelector({super.key, required this.onModelChanged});

  @override
  State<ModelSelector> createState() => _ModelSelectorState();
}

class _ModelSelectorState extends State<ModelSelector> {
  final ModelService _modelsService = ModelService();
  List<Map<String, dynamic>> _models = const [];
  String? _activeModelId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  Future<void> _loadModels() async {
    try {
      await _modelsService.refreshModels();
      final models = _modelsService.getModels();
      final active = _modelsService.getActiveModel();
      if (!mounted) return;
      setState(() {
        _models = models;
        final activeId = active['id']?.toString();
        _activeModelId = models.any((model) => model['id'] == activeId)
            ? activeId
            : null;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectModel(String? modelId) async {
    if (modelId == null) return;
    final switched = await _modelsService.switchModel(modelId);
    if (!mounted) return;
    if (switched) {
      setState(() => _activeModelId = modelId);
      widget.onModelChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.model_training, size: 18, color: Colors.white70),
          const SizedBox(width: 8),
          const Text(
            'النموذج:',
            style: TextStyle(fontSize: 12, color: Colors.white70),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<String>(
              value: _activeModelId,
              hint: Text(
                _loading ? 'جارٍ تحميل النماذج...' : 'لا يوجد نموذج محمّل',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              dropdownColor: Colors.grey.shade800,
              underline: const SizedBox.shrink(),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              isExpanded: true,
              items: _models.map((model) {
                final id = model['id']?.toString() ?? '';
                final name = model['name']?.toString() ?? id;
                final size = model['size']?.toString() ?? '';
                final isLoaded = model['id'] == _activeModelId;
                return DropdownMenuItem<String>(
                  value: id,
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 14,
                        color: isLoaded ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
                      if (size.isNotEmpty)
                        Text(
                          size,
                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: _selectModel,
            ),
          ),
        ],
      ),
    );
  }
}
