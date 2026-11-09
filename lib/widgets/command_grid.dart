import 'package:flutter/material.dart';
import '../core/theme.dart';

class CommandGrid extends StatelessWidget {
  final Function(String) onCommandSelected;
  
  const CommandGrid({super.key, required this.onCommandSelected});
  
  @override
  Widget build(BuildContext context) {
    final commands = [
      {'icon': Icons.analytics, 'title': 'تحليل بيانات', 'color': Colors.blue},
      {'icon': Icons.code, 'title': 'كود Python', 'color': Colors.green},
      {'icon': Icons.web, 'title': 'موقع ويب', 'color': const Color(0xFF1A73E8)},
      {'icon': Icons.api, 'title': 'إنشاء API', 'color': Colors.orange},
      {'icon': Icons.psychology, 'title': 'تعلم آلة', 'color': Colors.red},
      {'icon': Icons.auto_awesome, 'title': 'أتمتة', 'color': const Color(0xFF34A99F)},
      {'icon': Icons.description, 'title': 'تحليل نص', 'color': const Color(0xFF0A8F83)},
      {'icon': Icons.calculate, 'title': 'حسابات', 'color': const Color(0xFF1A73E8)},
    ];
    
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.5,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: commands.length,
      itemBuilder: (context, index) {
        final cmd = commands[index];
        return _buildCommandCard(
          icon: cmd['icon'] as IconData,
          title: cmd['title'] as String,
          color: cmd['color'] as Color,
          onTap: () => onCommandSelected(cmd['title']),
        );
      },
    );
  }
  
  Widget _buildCommandCard({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withOpacity(0.1), Colors.transparent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
