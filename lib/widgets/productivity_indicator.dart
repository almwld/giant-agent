import 'package:flutter/material.dart';
import '../core/theme.dart';

class ProductivityIndicator extends StatelessWidget {
  final int messagesCount;
  final int tasksCompleted;
  
  const ProductivityIndicator({
    super.key,
    required this.messagesCount,
    required this.tasksCompleted,
  });

  @override
  Widget build(BuildContext context) {
    final productivity = (tasksCompleted / (messagesCount + 1)) * 100;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.trending_up, size: 20),
              SizedBox(width: 8),
              Text(
                'إنتاجيتك اليوم',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: productivity / 100,
            backgroundColor: Colors.grey.shade300,
            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$tasksCompleted مكتملة', style: const TextStyle(fontSize: 12)),
              Text('${productivity.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}
