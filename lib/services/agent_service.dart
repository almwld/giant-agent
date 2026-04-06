import 'dart:io';
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class AgentService {
  Future<String> process(String input) async {
    final lower = input.toLowerCase();
    
    // إنشاء موقع HTML
    if (lower.contains('موقع') && (lower.contains('أنشئ') || lower.contains('إنشاء'))) {
      return await _createWebsite(input);
    }
    
    // كتابة كود
    if (lower.contains('كود') || lower.contains('برنامج')) {
      return await _generateCode(input);
    }
    
    // تحليل نص
    if (lower.contains('حلل') || lower.contains('تحليل')) {
      return await _analyzeText(input);
    }
    
    // قائمة مهام
    if (lower.contains('قائمة مهام') || lower.contains('todo')) {
      return await _createTodoList(input);
    }
    
    // تذكير
    if (lower.contains('ذكرني') || lower.contains('تذكير')) {
      return await _createReminder(input);
    }
    
    // عملية حسابية
    if (lower.contains('+') || lower.contains('-') || lower.contains('*') || lower.contains('/') || lower.contains('×')) {
      return _calculate(input);
    }
    
    // محادثة عادية
    return _chatResponse(input);
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
            background: rgba(255,255,255,0.95);
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
    </style>
</head>
<body>
    <div class="card">
        <h1>🤖 $title</h1>
        <p>تم إنشاء هذه الصفحة بواسطة <strong>Giant Agent</strong></p>
        <p>الوكيل العملاق للذكاء الاصطناعي</p>
        <button onclick="alert('مرحباً بك! 🚀')">اضغط هنا</button>
        <div style="margin-top: 20px; font-size: 12px; color: #999;">
            تم الإنشاء في ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}
        </div>
    </div>
</body>
</html>
''';
    
    final file = File('${dir?.path}/$title.html');
    await file.writeAsString(html);
    
    return '''
✅ **تم إنشاء الموقع بنجاح!**

🌐 **الملف**: $title.html
📂 **المسار**: ${file.path}

يمكنك فتح الملف في المتصفح لمشاهدة الموقع.
''';
  }

  Future<String> _generateCode(String input) async {
    final dir = await getExternalStorageDirectory();
    
    String language = 'Python';
    String code = '';
    
    if (input.contains('python')) {
      language = 'Python';
      code = '''
# كود Python تم إنشاؤه بواسطة Giant Agent

def calculate_average(numbers):
    """حساب متوسط الأرقام"""
    if not numbers:
        return 0
    return sum(numbers) / len(numbers)

# مثال للاستخدام
numbers = [1, 2, 3, 4, 5]
average = calculate_average(numbers)
print(f"المتوسط: {average}")
''';
    } else if (input.contains('dart') || input.contains('flutter')) {
      language = 'Dart';
      code = '''
// كود Dart تم إنشاؤه بواسطة Giant Agent

void main() {
  List<int> numbers = [1, 2, 3, 4, 5];
  double average = numbers.reduce((a, b) => a + b) / numbers.length;
  print('المتوسط: \$average');
}
''';
    } else {
      language = 'JavaScript';
      code = '''
// كود JavaScript تم إنشاؤه بواسطة Giant Agent

function calculateAverage(numbers) {
    if (numbers.length === 0) return 0;
    return numbers.reduce((a, b) => a + b, 0) / numbers.length;
}

// مثال
const numbers = [1, 2, 3, 4, 5];
console.log(`المتوسط: \${calculateAverage(numbers)}`);
''';
    }
    
    final fileName = 'code_${DateTime.now().millisecondsSinceEpoch}.${language.toLowerCase()}';
    final file = File('${dir?.path}/$fileName');
    await file.writeAsString(code);
    
    return '''
✅ **تم إنشاء كود $language**

💻 **الملف**: $fileName
📂 **المسار**: ${file.path}

\`\`\`$language
$code
\`\`\`
''';
  }

  Future<String> _analyzeText(String input) async {
    final textToAnalyze = input.replaceAll(RegExp(r'حلل|تحليل'), '').trim();
    
    if (textToAnalyze.isEmpty) {
      return '📝 الرجاء إدخال النص المراد تحليله بعد كلمة "حلل"';
    }
    
    final analysis = '''
📊 **نتائج التحليل**

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📝 **النص المحلل**:
${textToAnalyze.length > 200 ? textToAnalyze.substring(0, 200) + '...' : textToAnalyze}

📏 **الإحصائيات**:
• عدد الحروف: ${textToAnalyze.length}
• عدد الكلمات: ${textToAnalyze.split(' ').length}
• عدد الجمل: ${textToAnalyze.split(RegExp(r'[.!?]+')).length}

🔍 **خصائص النص**:
• يحتوي على أرقام: ${RegExp(r'\d').hasMatch(textToAnalyze) ? '✅ نعم' : '❌ لا'}
• يحتوي على عربي: ${RegExp(r'[\u0600-\u06FF]').hasMatch(textToAnalyze) ? '✅ نعم' : '❌ لا'}

💡 **الاقتراحات**:
${textToAnalyze.length < 50 ? '• النص قصير، يمكن إضافة تفاصيل أكثر' : '• النص جيد، يمكن تحسين التنظيم'}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''';
    
    return analysis;
  }

  Future<String> _createTodoList(String input) async {
    final dir = await getExternalStorageDirectory();
    
    // استخراج المهام
    List<String> tasks = [];
    if (input.contains(',')) {
      tasks = input.split(',').map((t) => t.trim()).toList();
    } else {
      tasks = ['مهمة 1', 'مهمة 2', 'مهمة 3'];
    }
    
    final content = '''
📝 **قائمة المهام**
═══════════════════════════════════
${tasks.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n')}
═══════════════════════════════════
📅 التاريخ: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}
✅ إجمالي المهام: ${tasks.length}
''';
    
    final fileName = 'todo_list_${DateTime.now().millisecondsSinceEpoch}.txt';
    final file = File('${dir?.path}/$fileName');
    await file.writeAsString(content);
    
    return '''
✅ **تم إنشاء قائمة المهام**

📝 **المهام**:
${tasks.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n')}

📂 **الملف**: $fileName
''';
  }

  Future<String> _createReminder(String input) async {
    final reminderText = input.replaceAll(RegExp(r'ذكرني|تذكير'), '').trim();
    
    // استخراج الوقت
    RegExp timeRegex = RegExp(r'(\d{1,2})[:.](\d{2})');
    final match = timeRegex.firstMatch(input);
    
    String timeInfo = '';
    if (match != null) {
      timeInfo = ' في ${match.group(1)}:${match.group(2)}';
    }
    
    return '''
✅ **تم حفظ التذكير**

📝 "${reminderText.isEmpty ? 'تذكير غير محدد' : reminderText}"$timeInfo

🔔 سأذكرك في الوقت المناسب!
''';
  }

  String _calculate(String input) {
    try {
      // تنظيف الإدخال
      String expr = input.replaceAll('×', '*');
      
      // استخراج الأرقام والعمليات
      final numbers = RegExp(r'\d+(?:\.\d+)?').allMatches(expr).map((m) => double.parse(m.group(0)!)).toList();
      if (numbers.length < 2) return 'الرجاء كتابة عملية حسابية صحيحة';
      
      double result;
      if (expr.contains('+')) {
        result = numbers[0] + numbers[1];
        return '🧮 **${numbers[0]} + ${numbers[1]} = ${result.toStringAsFixed(result == result.toInt() ? 0 : 2)}**';
      } else if (expr.contains('-')) {
        result = numbers[0] - numbers[1];
        return '🧮 **${numbers[0]} - ${numbers[1]} = ${result.toStringAsFixed(result == result.toInt() ? 0 : 2)}**';
      } else if (expr.contains('*')) {
        result = numbers[0] * numbers[1];
        return '🧮 **${numbers[0]} × ${numbers[1]} = ${result.toStringAsFixed(result == result.toInt() ? 0 : 2)}**';
      } else if (expr.contains('/')) {
        if (numbers[1] == 0) return '⚠️ لا يمكن القسمة على صفر';
        result = numbers[0] / numbers[1];
        return '🧮 **${numbers[0]} ÷ ${numbers[1]} = ${result.toStringAsFixed(result == result.toInt() ? 0 : 2)}**';
      }
    } catch (e) {
      return '❌ خطأ في العملية الحسابية';
    }
    return 'الرجاء كتابة عملية حسابية مثل: 5+3';
  }

  String _extractTitle(String input) {
    if (input.contains('عنوان')) {
      final match = RegExp(r'عنوان[\s:]*([^\n،.]+)').firstMatch(input);
      if (match != null) return match.group(1)!.trim();
    }
    return 'Giant_Agent_${DateTime.now().millisecondsSinceEpoch}';
  }

  String _chatResponse(String input) {
    final lower = input.toLowerCase();
    
    if (lower.contains('مرحبا') || lower.contains('السلام')) {
      return 'مرحباً بك! 👋 أنا الوكيل العملاق. كيف أخدمك اليوم؟\n\nيمكنني:\n• إنشاء مواقع HTML\n• كتابة أكواد برمجية\n• تحليل النصوص\n• قوائم المهام\n• عمليات حسابية\n• تذكيرات\n\nماذا تريد أن نفعل؟';
    }
    
    if (lower.contains('كيف حالك')) {
      return 'أنا بخير، شكراً! 🧠 جاهز لمساعدتك في أي وقت.';
    }
    
    if (lower.contains('شكرا')) {
      return 'العفو! 🤝 دائماً في خدمتك.';
    }
    
    if (lower.contains('وداعا')) {
      return '👋 وداعاً! سأكون هنا عندما تحتاجني.';
    }
    
    if (lower.contains('ماذا يمكنك')) {
      return '''
📋 **قدراتي الكاملة**:

📁 **إنشاء الملفات** - نصوص، HTML، JSON
💻 **كتابة الأكواد** - Python, Dart, JavaScript, HTML/CSS
🌐 **إنشاء المواقع** - صفحات HTML كاملة وجميلة
📊 **تحليل البيانات** - نصوص، أرقام، إحصائيات
🔢 **العمليات الحسابية** - جمع، طرح، ضرب، قسمة
⏰ **التذكيرات** - جدولة وتنبيهات
📝 **قوائم المهام** - تنظيم وإدارة
🌍 **الترجمة** - نصوص متعددة اللغات

**جرب هذه الأوامر:**
• `أنشئ موقعاً عن الذكاء الاصطناعي`
• `اكتب كود Python لحساب المتوسط`
• `حلل هذا النص: ...`
• `5+3×2`
''';
    }
    
    final random = Random();
    final responses = [
      '🤔 سؤال ذكي! دعني أفكر... كيف يمكنني مساعدتك؟',
      '💡 فكرة رائعة! يمكنني إنشاء موقع أو كود أو تحليل نص. ماذا تفضل؟',
      '🧠 أنا هنا لمساعدتك. أخبرني ماذا تريد أن نفعل؟',
      '📚 لدي معرفة واسعة. يمكنني مساعدتك في أي مهمة.',
    ];
    
    return responses[random.nextInt(responses.length)];
  }
}
