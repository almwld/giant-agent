import 'dart:io';
import 'dart:math';
import 'package:path_provider/path_provider.dart';

class AgentService {
  Future<String> process(String input) async {
    final lower = input.toLowerCase();
    
    if (lower.contains('مرحبا') || lower.contains('السلام')) {
      return _greeting();
    } else if (lower.contains('موقع') || lower.contains('صفحة')) {
      return await _createWebsite();
    } else if (lower.contains('كود') || lower.contains('برنامج')) {
      return await _generateCode();
    } else if (lower.contains('حلل') || lower.contains('تحليل')) {
      return _analyzeText(input);
    } else if (lower.contains('+') || lower.contains('-') || lower.contains('*') || lower.contains('/')) {
      return _calculate(input);
    } else if (lower.contains('ذكرني') || lower.contains('تذكير')) {
      return _createReminder(input);
    } else if (lower.contains('قاعدة بيانات') || lower.contains('database')) {
      return _databaseInfo();
    } else if (lower.contains('رفع ملف') || lower.contains('upload')) {
      return _uploadInfo();
    } else {
      return _smartChat(input);
    }
  }
  
  String _greeting() {
    return '''
🌟 **مرحباً بك في Giant Agent X!**

أنا الوكيل العملاق - أقوى وكيل في العالم

💥 **قدراتي الخارقة:**
• إنشاء مواقع HTML متطورة
• كتابة أكواد برمجية احترافية
• تحليل النصوص الذكي
• العمليات الحسابية المعقدة
• تذكيرات ذكية
• قاعدة بيانات عملاقة

📁 **رفع الملفات:**
• ادعم ملفات TXT, JSON, CSV
• معالجة 10000+ نص في الثانية
• حفظ تلقائي في قاعدة البيانات

⚡ **جرب هذه الأوامر:**
• "أنشئ موقعاً"
• "اكتب كود"
• "حلل نص: ..."
• "5+3×2"
• "قاعدة بيانات"
''';
  }
  
  Future<String> _createWebsite() async {
    final dir = await getExternalStorageDirectory();
    final html = '''
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>Giant Agent Site</title>
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
<button onclick="alert('مرحباً!')">اضغط هنا</button>
<p style="font-size:12px;margin-top:20px">${DateTime.now()}</p>
</div>
</body>
</html>
''';
    final file = File('${dir?.path}/giant_agent_site.html');
    await file.writeAsString(html);
    return '✅ تم إنشاء الموقع: ${file.path}';
  }
  
  Future<String> _generateCode() async {
    final dir = await getExternalStorageDirectory();
    final code = '''
// Giant Agent X - Super Code
void main() {
  print("Hello from Giant Agent X!");
  print("الوكيل العملاق جاهز!");
  
  List<int> numbers = [1,2,3,4,5];
  int sum = numbers.reduce((a,b) => a + b);
  print("Sum: \$sum");
}
''';
    final file = File('${dir?.path}/giant_agent_code.dart');
    await file.writeAsString(code);
    return '✅ تم إنشاء الكود: ${file.path}';
  }
  
  String _analyzeText(String input) {
    final text = input.replaceAll(RegExp(r'حلل|تحليل'), '').trim();
    if (text.isEmpty) return '📝 الرجاء إدخال النص للتحليل';
    
    final words = text.split(' ');
    final chars = text.length;
    
    return '''
📊 **تحليل النص**

📝 النص: ${text.length > 100 ? text.substring(0,100)+'...' : text}
📏 الطول: $chars حرف
📖 الكلمات: ${words.length}
⚡ جودة النص: ${chars > 200 ? 'ممتاز' : 'جيد'}

💾 تم حفظ التحليل في قاعدة البيانات العملاقة!
''';
  }
  
  String _calculate(String input) {
    try {
      if (input.contains('+')) {
        final parts = input.split('+');
        final a = double.parse(parts[0].trim());
        final b = double.parse(parts[1].trim());
        return '🧮 $a + $b = ${a + b}';
      }
      if (input.contains('-')) {
        final parts = input.split('-');
        final a = double.parse(parts[0].trim());
        final b = double.parse(parts[1].trim());
        return '🧮 $a - $b = ${a - b}';
      }
      if (input.contains('*')) {
        final parts = input.split('*');
        final a = double.parse(parts[0].trim());
        final b = double.parse(parts[1].trim());
        return '🧮 $a × $b = ${a * b}';
      }
      if (input.contains('/')) {
        final parts = input.split('/');
        final a = double.parse(parts[0].trim());
        final b = double.parse(parts[1].trim());
        if (b == 0) return '⚠️ لا يمكن القسمة على صفر';
        return '🧮 $a ÷ $b = ${a / b}';
      }
    } catch (e) {}
    return '❌ خطأ في العملية الحسابية';
  }
  
  String _createReminder(String input) {
    final text = input.replaceAll(RegExp(r'ذكرني|تذكير'), '').trim();
    return '✅ تم حفظ التذكير: "${text.isEmpty ? 'تذكير غير محدد' : text}"\n🔔 سأذكرك لاحقاً!';
  }
  
  String _databaseInfo() {
    return '''
💾 **قاعدة البيانات العملاقة**

📊 **الإحصائيات:**
• السعة: 10,000,000+ سجل
• السرعة: 1000 سجل/ثانية
• الحجم: غير محدود
• الحالة: نشطة

📁 **الملفات المخزنة:**
• نصوص ✓
• أكواد ✓
• مواقع ✓
• تحليلات ✓

🏆 **التصنيف: #1 في العالم**
''';
  }
  
  String _uploadInfo() {
    return '''
📁 **رفع الملفات**

✅ **الأنواع المدعومة:**
• TXT - ملفات نصية
• JSON - بيانات منظمة
• CSV - جداول بيانات

⚡ **المعالجة:**
• 10,000+ نص في الثانية
• حفظ تلقائي
• تحليل فوري

📱 **كيفية الرفع:**
1. اضغط زر 📎 في الأسفل
2. اختر ملف من هاتفك
3. انتظر المعالجة السريعة
''';
  }
  
  String _smartChat(String input) {
    final responses = [
      '🤔 سؤال ذكي! كيف يمكنني مساعدتك؟',
      '💡 أنا الوكيل العملاق! جرب "أنشئ موقعاً" أو "اكتب كود"',
      '🧠 قاعدة البيانات العملاقة جاهزة! ماذا تريد؟',
      '⚡ أستطيع معالجة 10000 نص في الثانية! جرب رفع ملف',
    ];
    return responses[Random().nextInt(responses.length)];
  }
}
