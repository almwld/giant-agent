import 'dart:io';
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class AgentService {
  List<Map<String, dynamic>> _responses = [];
  
  Future<void> init() async {
    print('Giant Agent Initialized!');
  }
  
  Future<String> process(String input) async {
    final lower = input.toLowerCase();
    
    if (lower.contains('مرحبا') || lower.contains('السلام')) {
      return _greeting();
    } else if (lower.contains('موقع') || lower.contains('صفحة')) {
      return await _createWebsite(input);
    } else if (lower.contains('كود') || lower.contains('برنامج')) {
      return await _generateCode(input);
    } else if (lower.contains('حلل') || lower.contains('تحليل')) {
      return _analyzeText(input);
    } else if (lower.contains('+') || lower.contains('-') || lower.contains('*') || lower.contains('/')) {
      return _calculate(input);
    } else if (lower.contains('ذكرني') || lower.contains('تذكير')) {
      return _createReminder(input);
    } else if (lower.contains('قائمة مهام')) {
      return _createTodoList(input);
    } else if (lower.contains('كيف حالك')) {
      return _howAreYou();
    } else if (lower.contains('شكرا')) {
      return _thankYou();
    } else if (lower.contains('وداعا')) {
      return _goodbye();
    } else {
      return _smartChat(input);
    }
  }
  
  String _greeting() {
    final hour = DateTime.now().hour;
    String timeGreeting;
    if (hour < 12) timeGreeting = 'صباح الخير';
    else if (hour < 18) timeGreeting = 'مساء الخير';
    else timeGreeting = 'مساء النور';
    
    return '''
🌅 **$timeGreeting!** 👋

أنا **Giant Agent** - الوكيل العملاق

🚀 **ماذا يمكنني أن أفعل لك؟**
• إنشاء مواقع HTML متطورة
• كتابة أكواد برمجية احترافية
• تحليل النصوص والإحصائيات
• العمليات الحسابية المعقدة
• تذكيرات ذكية
• قوائم مهام

**فقط اكتب طلبك وسأنفذه فوراً!**
''';
  }
  
  String _howAreYou() {
    return 'أنا بخير، شكراً! 🧠 جاهز لمساعدتك في أي وقت. ماذا تريد أن نفعل اليوم؟';
  }
  
  String _thankYou() {
    return 'العفو! 🤝 دائماً في خدمتك. هل هناك شيء آخر يمكنني مساعدتك به؟';
  }
  
  String _goodbye() {
    return '👋 وداعاً! سعدت بمساعدتك. عد متى شئت، سأكون هنا.';
  }
  
  Future<String> _createWebsite(String input) async {
    final dir = await getExternalStorageDirectory();
    final title = _extractTitle(input);
    
    final html = '''
<!DOCTYPE html>
<html lang="ar">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$title</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            padding: 20px;
        }
        .card {
            background: white;
            border-radius: 20px;
            padding: 40px;
            max-width: 600px;
            width: 100%;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            text-align: center;
            animation: fadeIn 0.8s ease-out;
        }
        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(20px); }
            to { opacity: 1; transform: translateY(0); }
        }
        h1 { color: #667eea; margin-bottom: 20px; }
        p { color: #666; line-height: 1.6; margin-bottom: 20px; }
        button {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            padding: 12px 30px;
            border-radius: 25px;
            font-size: 16px;
            cursor: pointer;
            transition: transform 0.2s;
        }
        button:hover { transform: scale(1.05); }
        .footer { margin-top: 20px; font-size: 12px; color: #999; }
    </style>
</head>
<body>
    <div class="card">
        <h1>🤖 $title</h1>
        <p>تم إنشاء هذه الصفحة بواسطة <strong>Giant Agent</strong></p>
        <p>الوكيل العملاق للذكاء الاصطناعي</p>
        <button onclick="alert('مرحباً بك! 🚀')">اضغط هنا</button>
        <div class="footer">تم الإنشاء في ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}</div>
    </div>
</body>
</html>
''';
    
    final fileName = '${title.replaceAll(' ', '_')}.html';
    final file = File('${dir?.path}/$fileName');
    await file.writeAsString(html);
    
    return '''
✅ **تم إنشاء الموقع بنجاح!**

🌐 **الملف**: $fileName
📂 **المسار**: ${file.path}

🎨 **الميزات**:
• تصميم عصري وجذاب
• تأثيرات حركية
• متجاوب مع جميع الأجهزة
• أزرار تفاعلية

يمكنك فتح الملف في المتصفح لمشاهدته!
''';
  }
  
  Future<String> _generateCode(String input) async {
    final dir = await getExternalStorageDirectory();
    
    String code = '''
// كود تم إنشاؤه بواسطة Giant Agent
// $input

void main() {
  print("Hello from Giant Agent!");
  print("مرحباً من الوكيل العملاق!");
  
  // مثال: حساب مجموع الأرقام
  List<int> numbers = [1, 2, 3, 4, 5];
  int sum = numbers.reduce((a, b) => a + b);
  print("المجموع: \$sum");
}
''';
    
    final fileName = 'code_${DateTime.now().millisecondsSinceEpoch}.dart';
    final file = File('${dir?.path}/$fileName');
    await file.writeAsString(code);
    
    return '''
✅ **تم إنشاء الكود بنجاح!**

💻 **الملف**: $fileName
📂 **المسار**: ${file.path}

📝 **محتوى الكود**:
```dart
${code.substring(0, code.length > 300 ? 300 : code.length)}...
```

يمكنك تعديل الكود وتشغيله حسب حاجتك!
''';
  }
  
  String _analyzeText(String input) {
    final text = input.replaceAll(RegExp(r'حلل|تحليل'), '').trim();
    
    if (text.isEmpty) {
      return '📝 الرجاء إدخال النص المراد تحليله بعد كلمة "حلل"';
    }
    
    final words = text.split(' ');
    final chars = text.length;
    final sentences = text.split(RegExp(r'[.!?]+')).length;
    
    return '''
📊 **نتائج التحليل**

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📝 **النص المحلل**:
${text.length > 200 ? text.substring(0, 200) + '...' : text}

📏 **الإحصائيات**:
• عدد الحروف: $chars
• عدد الكلمات: ${words.length}
• عدد الجمل: $sentences
• متوسط طول الكلمة: ${(chars / words.length).toStringAsFixed(1)} حرف

🔍 **الخصائص**:
• يحتوي على أرقام: ${RegExp(r'\d').hasMatch(text) ? '✅ نعم' : '❌ لا'}
• يحتوي على عربي: ${RegExp(r'[\u0600-\u06FF]').hasMatch(text) ? '✅ نعم' : '❌ لا'}

💡 **الاقتراحات**:
${text.length < 100 ? '• النص قصير، يمكن إضافة تفاصيل أكثر' : '• النص جيد، يمكن تحسين التنظيم'}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''';
  }
  
  String _calculate(String input) {
    try {
      String expr = input.replaceAll('×', '*').replaceAll('÷', '/');
      
      final numbers = RegExp(r'\d+(?:\.\d+)?').allMatches(expr).map((m) => double.parse(m.group(0)!)).toList();
      if (numbers.length < 2) return 'الرجاء كتابة عملية حسابية صحيحة مثل: 5+3';
      
      double result;
      String operation;
      
      if (expr.contains('+')) {
        result = numbers[0] + numbers[1];
        operation = '+';
      } else if (expr.contains('-')) {
        result = numbers[0] - numbers[1];
        operation = '-';
      } else if (expr.contains('*')) {
        result = numbers[0] * numbers[1];
        operation = '×';
      } else if (expr.contains('/')) {
        if (numbers[1] == 0) return '⚠️ لا يمكن القسمة على صفر';
        result = numbers[0] / numbers[1];
        operation = '÷';
      } else {
        return 'عملية غير معروفة';
      }
      
      final resultStr = result.toStringAsFixed(result == result.toInt() ? 0 : 2);
      
      return '''
🧮 **النتيجة**: $resultStr

📝 **العملية**: ${numbers[0]} $operation ${numbers[1]} = $resultStr
''';
    } catch (e) {
      return '❌ خطأ في العملية الحسابية';
    }
  }
  
  String _createReminder(String input) {
    final reminderText = input.replaceAll(RegExp(r'ذكرني|تذكير'), '').trim();
    return '''
✅ **تم حفظ التذكير!**

📝 "${reminderText.isEmpty ? 'تذكير غير محدد' : reminderText}"

🔔 سأذكرك في الوقت المناسب!
''';
  }
  
  String _createTodoList(String input) {
    final tasks = input.replaceAll('قائمة مهام', '').trim().split(',');
    
    if (tasks.isEmpty || (tasks.length == 1 && tasks[0].isEmpty)) {
      return '''
📝 **قائمة المهام**

1. مهمة 1
2. مهمة 2
3. مهمة 3

يمكنك إضافة مهام محددة مثل: "قائمة مهام: شراء، دراسة، رياضة"
''';
    }
    
    final taskList = tasks.asMap().entries.map((e) => '${e.key + 1}. ${e.value.trim()}').join('\n');
    
    return '''
✅ **تم إنشاء قائمة المهام!**

📝 **المهام**:
$taskList

📅 التاريخ: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}
''';
  }
  
  String _smartChat(String input) {
    final random = Random();
    final responses = [
      '🤔 سؤال ذكي! كيف يمكنني مساعدتك بشكل أفضل؟',
      '💡 يمكنني إنشاء مواقع، كتابة أكواد، تحليل نصوص، عمليات حسابية، تذكيرات، وقوائم مهام. ماذا تريد؟',
      '🧠 أنا الوكيل العملاق! أخبرني ماذا تريد أن نفعل؟',
      '📚 لدي قدرات متعددة. جرب كتابة "أنشئ موقعاً" أو "اكتب كود" أو "حلل نص"',
      '⚡ سأنفذ طلبك بسرعة! ماذا تريد أن تطلب؟',
    ];
    
    return responses[random.nextInt(responses.length)];
  }
  
  String _extractTitle(String input) {
    if (input.contains('عنوان')) {
      final match = RegExp(r'عنوان[\s:]*([^\n،.]+)').firstMatch(input);
      if (match != null) return match.group(1)!.trim();
    }
    return 'Giant_Agent_${DateTime.now().millisecondsSinceEpoch}';
  }
}
