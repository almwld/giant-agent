import 'package:flutter/material.dart';

class QuickActions extends StatelessWidget {
  final Function(String) onTap;

  const QuickActions({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> actions = [
      {'icon': Icons.chat, 'label': 'مرحبا', 'color': Colors.blue, 'command': 'مرحبا'},
      {'icon': Icons.web, 'label': 'موقع', 'color': Colors.green, 'command': 'أنشئ موقعاً'},
      {'icon': Icons.code, 'label': 'كود', 'color': Colors.orange, 'command': 'اكتب كود'},
      {'icon': Icons.analytics, 'label': 'تحليل', 'color': Colors.purple, 'command': 'حلل نص: الذكاء الاصطناعي هو مستقبل التكنولوجيا'},
      {'icon': Icons.calculate, 'label': 'حساب', 'color': Colors.red, 'command': '15+27'},
      {'icon': Icons.model_training, 'label': 'نماذج', 'color': Colors.teal, 'command': 'النماذج'},
      {'icon': Icons.cloud_upload, 'label': 'رفع', 'color': Colors.cyan, 'command': 'رفع ملف'},
      {'icon': Icons.storage, 'label': 'قاعدة بيانات', 'color': Colors.indigo, 'command': 'قاعدة بيانات'},
    ];

    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final action = actions[index];
          return _QuickActionChip(
            icon: action['icon'],
            label: action['label'],
            color: action['color'],
            onTap: () => onTap(action['command']),
          );
        },
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withOpacity(0.2), color.withOpacity(0.1)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: color.withOpacity(0.5), width: 1),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
