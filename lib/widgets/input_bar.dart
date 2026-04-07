import 'package:flutter/material.dart';
import '../core/theme.dart';

class InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final VoidCallback onImage;
  final bool isLoading;
  
  const InputBar({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onAttach,
    required this.onImage,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // زر رفع ملف
            Container(
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.attach_file),
                onPressed: onAttach,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            // زر رفع صورة
            Container(
              decoration: BoxDecoration(
                color: AppTheme.secondary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.image),
                onPressed: onImage,
                color: AppTheme.secondary,
              ),
            ),
            const SizedBox(width: 12),
            // حقل النص
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppTheme.darkSurface
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: TextField(
                  controller: controller,
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppTheme.darkText
                        : AppTheme.text,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'اكتب رسالتك...',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // زر الإرسال
            Container(
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: onSend,
                      color: Colors.white,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
