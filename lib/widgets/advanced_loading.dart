import 'package:flutter/material.dart';
import '../core/theme.dart';

class AdvancedLoading extends StatelessWidget {
  final String message;
  
  const AdvancedLoading({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }
}
