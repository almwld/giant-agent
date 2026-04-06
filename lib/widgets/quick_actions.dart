import 'package:flutter/material.dart';

class QuickActions extends StatelessWidget {
  final Function(String) onTap;
  
  const QuickActions({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final List<String> actions = [
      'مرحبا',
      'أنشئ موقعاً',
      'اكتب كود',
      'حلل نص',
      '5+3',
      'قائمة مهام',
    ];

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return ActionChip(
            label: Text(actions[index]),
            onPressed: () => onTap(actions[index]),
            backgroundColor: const Color(0xFF2D2D2D),
            labelStyle: const TextStyle(color: Colors.white),
          );
        },
      ),
    );
  }
}
