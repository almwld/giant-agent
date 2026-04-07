import 'package:flutter/material.dart';
import '../core/theme.dart';

class WordCounter extends StatelessWidget {
  final String text;
  
  const WordCounter({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final words = text.split(' ').length;
    final chars = text.length;
    final sentences = text.split(RegExp(r'[.!?]+')).length;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStat('📝', '$words', 'كلمة'),
          _buildStat('🔤', '$chars', 'حرف'),
          _buildStat('📄', '$sentences', 'جملة'),
        ],
      ),
    );
  }
  
  Widget _buildStat(String icon, String value, String label) {
    return Column(
      children: [
        Text(icon, style: const TextStyle(fontSize: 20)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}
