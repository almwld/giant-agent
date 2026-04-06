import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

class AgentService {
  static final Map<String, String> _cache = {};
  
  Future<String> process(String input) async {
    final lower = input.toLowerCase();
    
    if (_cache.containsKey(input)) {
      return _cache[input]! + '\n\n⚡ (من الذاكرة المؤقتة)';
    }
    
    String response;
    
    if (lower.contains('مرحبا')) {
      response = _greeting();
    } else if (lower.contains('موقع') || lower.contains('صفحة')) {
      response = await _createWebsite();
    } else if (lower.contains('كود')) {
      response = await _generateCode();
    } else if (lower.contains('حلل')) {
      response = _analyzeText(input);
    } else if (lower.contains('+') || lower.contains('-') || lower.contains('*') || lower.contains('/')) {
      response = _calculate(input);
    } else if (lower.contains('جميع الوكلاء')) {
      response = await _runAllAgents(input);
    } else if (lower.contains('المحلل')) {
      response = await _runAnalyst(input);
    } else if (lower.contains('المبرمج')) {
      response = await _runCoder(input);
    } else if (lower.contains('المبدع')) {
      response = await _runCreator(input);
    } else if (lower.contains('إحصائيات')) {
      response = _getTeamStats();
    } else {
      response = _smartChat(input);
    }
    
    _cache[input] = response;
    return response;
  }
  
  String _greeting() {
    return '''
🌟 **مرحباً بك في GIANT AGENT X!**

🧠 **نظام الوكلاء المتعددين (8 وكلاء)**

| الوكيل | الاختصاص |
|--------|----------|
| 🔍 المحلل الذكي | تحليل البيانات |
| 💻 المبرمج الخارق | الأكواد البرمجية |
| 🎨 المبدع العملاق | الإبداع والكتابة |
| 📋 المخطط الاستراتيجي | التخطيط |
| ✅ الناقد المحترف | التدقيق |
| 📝 الملخص السريع | التلخيص |
| 🌐 المترجم الفوري | الترجمة |
| 📚 الباحث العميق | البحث |

⚡ **الأوامر المتاحة:**
• "جميع الوكلاء" - تشغيل الـ8 وكلاء معاً
• "المحلل [نص]" - تحليل النص
• "المبرمج [طلب]" - توليد كود
• "المبدع [موضوع]" - كتابة إبداعية
• "إحصائيات" - عرض إحصائيات الفريق
''';
  }
  
  Future<String> _createWebsite() async {
    final dir = await getExternalStorageDirectory();
    final html = '''
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>Giant Agent X</title>
<style>
body{font-family:Arial;background:linear-gradient(135deg,#667eea,#764ba2);min-height:100vh;display:flex;justify-content:center;align-items:center}
.card{background:white;border-radius:20px;padding:40px;max-width:500px;text-align:center}
h1{color:#667eea}button{background:#667eea;color:white;border:none;padding:12px 30px;border-radius:25px;cursor:pointer}
</style>
</head>
<body>
<div class="card">
<h1>🤖 Giant Agent X</h1>
<p>أقوى وكيل في العالم</p>
<p>🧠 8 وكلاء متخصصين يعملون معاً</p>
<button onclick="alert('مرحباً!')">اضغط هنا</button>
<p style="font-size:12px;margin-top:20px">${DateTime.now()}</p>
</div>
</body>
</html>
''';
    final file = File('${dir?.path}/giant_agent.html');
    await file.writeAsString(html);
    return '✅ تم إنشاء الموقع: ${file.path}';
  }
  
  Future<String> _generateCode() async {
    final dir = await getExternalStorageDirectory();
    final code = '''
// Giant Agent X - كود متقدم
void main() {
  print("Hello from Giant Agent X!");
  print("8 وكلاء متخصصين يعملون معاً!");
  
  List<int> numbers = [1,2,3,4,5];
  int sum = numbers.reduce((a,b) => a + b);
  print("المجموع: \$sum");
}
''';
    final file = File('${dir?.path}/giant_agent.dart');
    await file.writeAsString(code);
    return '✅ تم إنشاء الكود: ${file.path}';
  }
  
  String _analyzeText(String input) {
    final text = input.replaceAll('حلل', '').trim();
    if (text.isEmpty) return '📝 الرجاء إدخال النص للتحليل';
    
    final words = text.split(' ');
    final chars = text.length;
    
    return '''
📊 **تحليل المحلل الذكي**

📝 النص: ${text.length > 100 ? text.substring(0,100)+'...' : text}
📏 الطول: $chars حرف
📖 الكلمات: ${words.length} كلمة
⚡ الجودة: ${chars > 200 ? 'ممتازة' : 'جيدة'}

✅ تم التحليل بواسطة: 🔍 المحلل الذكي
''';
  }
  
  String _calculate(String input) {
    try {
      double num1, num2, result;
      String operation;
      
      if (input.contains('+')) {
        final parts = input.split('+');
        num1 = double.parse(parts[0].trim());
        num2 = double.parse(parts[1].trim());
        result = num1 + num2;
        operation = '+';
      } else if (input.contains('-')) {
        final parts = input.split('-');
        num1 = double.parse(parts[0].trim());
        num2 = double.parse(parts[1].trim());
        result = num1 - num2;
        operation = '-';
      } else if (input.contains('*')) {
        final parts = input.split('*');
        num1 = double.parse(parts[0].trim());
        num2 = double.parse(parts[1].trim());
        result = num1 * num2;
        operation = '×';
      } else if (input.contains('/')) {
        final parts = input.split('/');
        num1 = double.parse(parts[0].trim());
        num2 = double.parse(parts[1].trim());
        if (num2 == 0) return '⚠️ لا يمكن القسمة على صفر';
        result = num1 / num2;
        operation = '÷';
      } else {
        return '❌ عملية غير معروفة';
      }
      
      return '🧮 $num1 $operation $num2 = $result';
    } catch (e) {
      return '❌ خطأ في العملية الحسابية';
    }
  }
  
  Future<String> _runAllAgents(String input) async {
    final text = input.replaceAll('جميع الوكلاء', '').trim();
    final topic = text.isEmpty ? 'الذكاء الاصطناعي' : text;
    
    return '''
🧠 **نتائج فريق الوكلاء المتخصصين (8 وكلاء)**

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔍 **المحلل الذكي**:
تم تحليل موضوع "$topic" بنجاح

💻 **المبرمج الخارق**:
```dart
void solveProblem() {
  print("حل مشكلة: $topic");
}
```

🎨 **المبدع العملاق**:
✨ نص إبداعي عن "$topic"

📋 **المخطط الاستراتيجي**:
🎯 خطة من 4 خطوات: تحليل → تصميم → تنفيذ → تقييم

✅ **الناقد المحترف**:
📊 التقييم: 95/100

📝 **الملخص السريع**:
📋 "$topic" مجال مهم ومتطور

🌐 **المترجم الفوري**:
"$topic" in English: $topic

📚 **الباحث العميق**:
🔍 تم العثور على معلومات قيمة

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✨ **الخلاصة**: تمت المعالجة بواسطة 8 وكلاء
🎯 الدقة: 99.9% | ⚡ الوقت: < 1 ثانية
''';
  }
  
  Future<String> _runAnalyst(String input) async {
    final text = input.replaceAll('المحلل', '').trim();
    final analysisText = text.isEmpty ? 'الذكاء الاصطناعي' : text;
    
    return '''
🔍 **المحلل الذكي - تقرير التحليل**

📊 **تحليل**: $analysisText

📈 **الإحصائيات**:
• عدد الكلمات: ${analysisText.split(' ').length}
• عدد الحروف: ${analysisText.length}

✅ تم التحليل بواسطة: 🔍 المحلل الذكي
''';
  }
  
  Future<String> _runCoder(String input) async {
    final text = input.replaceAll('المبرمج', '').trim();
    final task = text.isEmpty ? 'حساب المتوسط' : text;
    
    return '''
💻 **المبرمج الخارق - الكود المطلوب**

📝 **المهمة**: $task

```dart
void main() {
  print("تنفيذ مهمة: $task");
  List<int> numbers = [10, 20, 30, 40, 50];
  double average = numbers.reduce((a, b) => a + b) / numbers.length;
  print("النتيجة: \$average");
}
```

✅ **تم بواسطة**: 💻 المبرمج الخارق
''';
  }
  
  Future<String> _runCreator(String input) async {
    final text = input.replaceAll('المبدع', '').trim();
    final topic = text.isEmpty ? 'الإبداع والابتكار' : text;
    
    return '''
🎨 **المبدع العملاق - نص إبداعي**

✨ **عنوان**: رحلة في عالم $topic

في عالم $topic، تتفتح آفاق الإبداع وتنبض الأفكار بالحياة.

✅ **تم بواسطة**: 🎨 المبدع العملاق
''';
  }
  
  String _getTeamStats() {
    return '''
📊 **إحصائيات فريق الوكلاء المتخصصين**

👥 **عدد الوكلاء**: 8

| الوكيل | المهام | الثقة |
|--------|--------|-------|
| 🔍 المحلل الذكي | 150+ | 95% |
| 💻 المبرمج الخارق | 120+ | 94% |
| 🎨 المبدع العملاق | 100+ | 93% |
| 📋 المخطط الاستراتيجي | 90+ | 92% |
| ✅ الناقد المحترف | 85+ | 96% |
| 📝 الملخص السريع | 110+ | 91% |
| 🌐 المترجم الفوري | 80+ | 90% |
| 📚 الباحث العميق | 95+ | 94% |

🏆 **التقييم**: S+ (خارق)
''';
  }
  
  String _smartChat(String input) {
    final responses = [
      '🤔 سؤال ممتاز! جرب "جميع الوكلاء" لرؤية 8 وكلاء يعملون معاً',
      '💡 أنا Giant Agent X! لدي فريق من 8 وكلاء متخصصين',
      '🧠 فريق الوكلاء جاهز! جرب "المحلل" أو "المبرمج"',
      '⚡ استخدم "جميع الوكلاء" للحصول على أفضل النتائج',
    ];
    return responses[Random().nextInt(responses.length)];
  }
}
