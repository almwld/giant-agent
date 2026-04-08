import 'package:flutter/material.dart';

class ModelCard extends StatelessWidget {
  final Map<String, dynamic> model;
  final bool isActive;
  final VoidCallback onTap;
  
  const ModelCard({
    super.key,
    required this.model,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: isActive ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isActive ? BorderSide(color: Colors.green.shade400, width: 2) : BorderSide.none,
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isActive ? Colors.green : Colors.grey.shade300,
          child: Icon(
            isActive ? Icons.check : Icons.model_training,
            color: Colors.white,
            size: 20,
          ),
        ),
        title: Text(
          model['name'],
          style: TextStyle(
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Text('${model['size']} MB • ${model['type']}'),
        trailing: isActive
            ? Chip(
                label: const Text('نشط'),
                backgroundColor: Colors.green.shade100,
                labelStyle: TextStyle(color: Colors.green.shade700),
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}
