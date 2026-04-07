import 'package:flutter/material.dart';
import '../core/theme.dart';

class LeaderboardCard extends StatelessWidget {
  final int rank;
  final String name;
  final int points;
  final int level;
  
  const LeaderboardCard({
    super.key,
    required this.rank,
    required this.name,
    required this.points,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: rank <= 3 ? AppTheme.primary.withOpacity(0.1) : null,
        borderRadius: BorderRadius.circular(12),
        border: rank <= 3 ? Border.all(color: AppTheme.primary) : null,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: rank == 1 ? Colors.amber :
                     rank == 2 ? Colors.grey :
                     rank == 3 ? Colors.brown : Colors.grey.shade300,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$rank',
                style: TextStyle(
                  color: rank <= 3 ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'المستوى $level',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$points',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const Text(
                'نقطة',
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
