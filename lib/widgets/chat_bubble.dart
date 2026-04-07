import 'package:flutter/material.dart';
import '../core/theme.dart';

class ChatBubble extends StatelessWidget {
  final String message;
  final bool isUser;
  final DateTime time;
  final String? modelName;
  
  const ChatBubble({
    super.key,
    required this.message,
    required this.isUser,
    required this.time,
    this.modelName,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        child: Column(
          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // اسم المستخدم/النموذج
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 12, bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isUser ? Icons.person : Icons.bolt,
                    size: 12,
                    color: isUser ? AppTheme.textLight : AppTheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isUser ? 'أنت' : (modelName ?? 'Giant Agent'),
                    style: TextStyle(
                      fontSize: 10,
                      color: isUser ? AppTheme.textLight : AppTheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            // فقاعة الرسالة
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: isUser
                    ? AppTheme.primaryGradient
                    : LinearGradient(
                        colors: isDark
                            ? [AppTheme.darkSurface, AppTheme.darkSurface]
                            : [Colors.white, Colors.grey.shade50],
                      ),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isUser ? 20 : 8),
                  bottomRight: Radius.circular(isUser ? 8 : 20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    message,
                    style: TextStyle(
                      color: isUser ? Colors.white : (isDark ? AppTheme.darkText : AppTheme.text),
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 10,
                      color: isUser ? Colors.white70 : AppTheme.textLight,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
