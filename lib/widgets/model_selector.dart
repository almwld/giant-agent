import 'package:flutter/material.dart';
import '../services/model_service.dart';

class ModelSelector extends StatefulWidget {
  final VoidCallback onModelChanged;

  const ModelSelector({super.key, required this.onModelChanged});

  @override
  State<ModelSelector> createState() => _ModelSelectorState();
}

class _ModelSelectorState extends State<ModelSelector> {
  List<Map<String, dynamic>> _models = [];
  String _activeModelId = 'default';

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  Future<void> _loadModels() async {
    final models = await ModelService.getAvailableModels();
    final active = ModelService.getActiveModel();
    setState(() {
      _models = models;
      _activeModelId = active['id'];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.model_training, size: 18, color: Colors.white70),
          const SizedBox(width: 8),
          const Text('النموذج:', style: TextStyle(fontSize: 12, color: Colors.white70)),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<String>(
              value: _activeModelId,
              dropdownColor: Colors.grey.shade800,
              underline: Container(),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              isExpanded: true,
              items: _models.map((model) {
                return DropdownMenuItem<String>(
                  value: model['id'],
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, size: 14, color: model['status'] == 'active' ? Colors.green : Colors.grey),
                      const SizedBox(width: 8),
                      Text(model['name']),
                      const SizedBox(width: 8),
                      Text('(${model['size']})', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) async {
                if (value != null) {
                  await ModelService.switchModel(value);
                  _activeModelId = value;
                  widget.onModelChanged();
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
