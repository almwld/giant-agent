import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;

class AIEngine {
  static final AIEngine _instance = AIEngine._internal();
  factory AIEngine() => _instance;
  AIEngine._internal();
  
  // تحليل المشاعر المتقدم
  String analyzeSentiment(String text) {
    final positive = ['good', 'great', 'excellent', 'amazing', 'wonderful', 'happy', 'joy', 'love', 'perfect', 'beautiful'];
    final negative = ['bad', 'terrible', 'awful', 'horrible', 'sad', 'angry', 'hate', 'worst', 'poor', 'ugly'];
    
    final lower = text.toLowerCase();
    int posCount = positive.where((w) => lower.contains(w)).length;
    int negCount = negative.where((w) => lower.contains(w)).length;
    
    if (posCount > negCount) return 'positive';
    if (negCount > posCount) return 'negative';
    return 'neutral';
  }
  
  // توليد ردود ذكية
  String generateSmartResponse(String input, String sentiment) {
    final lower = input.toLowerCase();
    
    if (lower.contains('مرحبا') || lower.contains('السلام')) {
      return _getGreeting();
    }
    
    if (lower.contains('كيف حالك')) {
      return 'أنا بخير، شكراً! 🧠 جاهز لمساعدتك في أي وقت.';
    }
    
    if (lower.contains('شكرا')) {
      return 'العفو! 🤝 دائماً في خدمتك.';
    }
    
    if (lower.contains('وداعا')) {
      return 'وداعاً! 👋 سعدت بمساعدتك.';
    }
    
    if (sentiment == 'positive') {
      return '😊 سعيد أنك سعيد! كيف يمكنني مساعدتك أكثر؟';
    } else if (sentiment == 'negative') {
      return '😔 آسف أنك تشعر بهذا. كيف يمكنني مساعدتك لتحسين مزاجك؟';
    }
    
    return _getRandomResponse();
  }
  
  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return '🌅 صباح الخير! كيف يمكنني مساعدتك اليوم؟';
    if (hour < 18) return '🌞 مساء الخير! ماذا تريد أن نفعل؟';
    return '🌙 مساء النور! كيف أخدمك؟';
  }
  
  String _getRandomResponse() {
    final responses = [
      'سؤال رائع! دعني أفكر في الأمر...',
      'هذا مثير للاهتمام! أخبرني أكثر.',
      'أفهم ما تقصده. كيف يمكنني مساعدتك؟',
      'شكراً على مشاركتك. ماذا تريد أن تعرف؟',
    ];
    return responses[Random().nextInt(responses.length)];
  }
  
  // توليد أفكار إبداعية
  String generateIdeas(String topic) {
    final ideas = [
      'ابتكار تطبيق ذكي باستخدام الذكاء الاصطناعي',
      'إنشاء موقع ويب تفاعلي',
      'تطوير روبوت محادثة متقدم',
      'تحليل بيانات ضخمة واستخراج أنماط',
      'أتمتة المهام اليومية',
    ];
    return '''
💡 **أفكار إبداعية حول $topic:**

${ideas.map((i) => '• $i').join('\n')}

هل تريد تفاصيل عن أي فكرة؟
''';
  }
  
  // حل المشكلات
  String solveProblem(String problem) {
    return '''
🔧 **حل المشكلة: $problem**

📋 **خطوات الحل:**
1. تحليل المشكلة بدقة
2. تحديد الأسباب المحتملة
3. اقتراح الحلول المناسبة
4. تنفيذ أفضل حل
5. متابعة النتائج

✅ **الحل المقترح:** يمكن استخدام الذكاء الاصطناعي لتحليل ومعالجة هذه المشكلة بشكل تلقائي وفعال.

هل تريد تفاصيل أكثر عن أي خطوة؟
''';
  }
}
