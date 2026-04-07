import 'package:flutter/material.dart';
import '../core/theme.dart';

class AchievementCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final bool isUnlocked;
  final int progress;
  
  const AchievementCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    this.isUnlocked = false,
    this.progress = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: isUnlocked 
            ? AppTheme.primaryGradient 
            : LinearGradient(
                colors: [Colors.grey.shade300, Colors.grey.shade200],
              ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                if (!isUnlocked) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress / 100,
                    backgroundColor: Colors.white.withOpacity(0.3),
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$progress%',
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ],
              ],
            ),
          ),
          if (isUnlocked)
            const Icon(Icons.emoji_events, color: Colors.amber, size: 30),
        ],
      ),
    );
  }
}
