import 'package:flutter/material.dart';
import '../core/theme.dart';

class FutureMessageBubble extends StatelessWidget {
  final String message;
  final bool isUser;
  final DateTime time;
  final double fontSize;

  const FutureMessageBubble({
    super.key,
    required this.message,
    required this.isUser,
    required this.time,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          gradient: isUser
              ? AppTheme.secondaryGradient
              : LinearGradient(
                  colors: isDark
                      ? [AppTheme.cosmicPurple.withOpacity(0.2), AppTheme.cyberBlue.withOpacity(0.1)]
                      : [Colors.grey.shade100, Colors.grey.shade50],
                ),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(24),
            topRight: const Radius.circular(24),
            bottomLeft: Radius.circular(isUser ? 24 : 8),
            bottomRight: Radius.circular(isUser ? 8 : 24),
          ),
          border: isUser
              ? null
              : Border.all(
                  color: AppTheme.primaryColor.withOpacity(0.3),
                  width: 1,
                ),
          boxShadow: [
            BoxShadow(
              color: (isUser ? AppTheme.neonPink : AppTheme.primaryColor).withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              message,
              style: TextStyle(
                color: isUser ? Colors.white : (isDark ? Colors.white : Colors.black87),
                fontSize: fontSize,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isUser ? Icons.person_outline : Icons.bolt,
                  size: 12,
                  color: isUser ? Colors.white70 : AppTheme.primaryColor,
                ),
                const SizedBox(width: 4),
                Text(
                  '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 10,
                    color: isUser ? Colors.white70 : AppTheme.textLightColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
