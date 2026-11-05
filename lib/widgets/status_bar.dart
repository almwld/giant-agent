import 'package:flutter/material.dart';

class StatusBar extends StatelessWidget {
  final String modelName;
  final int processedFiles;
  final String speed;

  const StatusBar({
    super.key,
    required this.modelName,
    required this.processedFiles,
    required this.speed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.deepPurple.shade900, Colors.deepPurple.shade700],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatusItem(Icons.memory, 'MODEL', modelName),
          Container(width: 1, height: 20, color: Colors.white24),
          _buildStatusItem(Icons.folder, 'FILES', '$processedFiles'),
          Container(width: 1, height: 20, color: Colors.white24),
          _buildStatusItem(Icons.speed, 'SPEED', speed),
        ],
      ),
    );
  }

  Widget _buildStatusItem(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.white70),
        const SizedBox(width: 6),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 8, color: Colors.white54)),
            Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
      ],
    );
  }
}
