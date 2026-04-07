import 'dart:math';

class VisualAnalytics {
  static final VisualAnalytics _instance = VisualAnalytics._internal();
  factory VisualAnalytics() => _instance;
  VisualAnalytics._internal();
  
  // تحليل نشاط المستخدم
  Map<String, dynamic> analyzeUserActivity(List<Map<String, dynamic>> messages) {
    final userMessages = messages.where((m) => m['isUser'] == true).length;
    final agentMessages = messages.length - userMessages;
    final avgLength = messages.fold<int>(0, (sum, m) => sum + m['content'].length) ~/ messages.length;
    
    return {
      'user_messages': userMessages,
      'agent_messages': agentMessages,
      'total_messages': messages.length,
      'avg_message_length': avgLength,
      'engagement_score': (userMessages / (messages.length + 1) * 100).toStringAsFixed(1),
    };
  }
  
  // توليد تقرير مرئي
  String generateVisualReport(Map<String, dynamic> analytics) {
    final engagement = double.parse(analytics['engagement_score']);
    String rating = '';
    if (engagement > 70) rating = '🔥 ممتاز';
    else if (engagement > 40) rating = '👍 جيد';
    else rating = '📈 يحتاج تحسين';
    
    return '''
📊 **تقرير التحليلات البصرية**

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

👤 **رسائلك:** ${analytics['user_messages']}
🤖 **ردودي:** ${analytics['agent_messages']}
💬 **إجمالي الرسائل:** ${analytics['total_messages']}
📏 **متوسط الطول:** ${analytics['avg_message_length']} حرف

📈 **معدل التفاعل:** ${analytics['engagement_score']}% $rating

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

💡 **نصيحة:** ${_getTip(engagement)}
''';
  }
  
  String _getTip(double engagement) {
    if (engagement > 70) {
      return 'استمر بنفس المستوى الرائع! 🚀';
    } else if (engagement > 40) {
      return 'جرب أوامر جديدة لتحسين التفاعل 💡';
    }
    return 'استخدم المزيد من الأوامر المتنوعة 📝';
  }
}
