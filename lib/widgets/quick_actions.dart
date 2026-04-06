import 'package:flutter/material.dart';

class QuickActions extends StatelessWidget {
  final Function(String) onTap;
  
  const QuickActions({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> actions = [
      {'icon': Icons.code, 'text': 'اكتب كود', 'color': Colors.blue},
      {'icon': Icons.web, 'text': 'أنشئ موقعاً', 'color': Colors.green},
      {'icon': Icons.analytics, 'text': 'حلل نصاً', 'color': Colors.orange},
      {'icon': Icons.calculate, 'text': '5+3×2', 'color': Colors.purple},
      {'icon': Icons.alarm, 'text': 'ذكرني', 'color': Colors.red},
      {'icon': Icons.star, 'text': 'متفوق', 'color': Colors.amber},
    ];

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final action = actions[index];
          return ActionChip(
            avatar: Icon(action['icon'], size: 16, color: Colors.white),
            label: Text(action['text']),
            onPressed: () => onTap(action['text']),
            backgroundColor: action['color'].withOpacity(0.2),
            labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          );
        },
      ),
    );
  }
}
