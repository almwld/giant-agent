import 'package:flutter/material.dart';
import '../core/theme.dart';

class DailyQuote extends StatelessWidget {
  const DailyQuote({super.key});

  @override
  Widget build(BuildContext context) {
    final quotes = [
      'الإبداع هو الذكاء الذي يمرح',
      'المستقبل ملك لأولئك الذين يؤمنون بجمال أحلامهم',
      'لا شيء مستحيل، الكلمة نفسها تقول أنا ممكن',
      'التغيير يبدأ من الداخل',
      'كن التغيير الذي تريد رؤيته في العالم',
    ];
    
    final today = DateTime.now().day;
    final quote = quotes[today % quotes.length];
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Icon(Icons.format_quote, color: Colors.white, size: 30),
          const SizedBox(height: 8),
          Text(
            quote,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '- حكمة اليوم',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
