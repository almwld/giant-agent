import 'package:flutter/material.dart';

class WordCounter extends StatelessWidget {
  final String text;
  
  const WordCounter({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final words = text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
    final chars = text.length;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.text_fields, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(
            '$words كلمة | $chars حرف',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
