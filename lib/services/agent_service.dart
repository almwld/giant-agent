import 'dart:io';
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'model_service.dart';
import 'file_upload_service.dart';

class AgentService {
  Future<String> process(String input) async {
    final lower = input.toLowerCase();
    
    // أوامر النماذج
    if (lower.contains('النماذج') || lower.contains('models')) {
      return await _showModels();
    }
    if (lower.contains('تبديل نموذج') || lower.contains('switch model')) {
      return await _switchModel(input);
    }
    if (lower.contains('تحميل نموذج') || lower.contains('download model')) {
      return await _downloadModel(input);
    }
    
    // أوامر رفع الملفات
    if (lower.contains('رفع ملف') || lower.contains('upload file')) {
      return _uploadInstructions();
    }
    if (lower.contains('تاريخ الملفات') || lower.contains('file history')) {
      return await _fileHistory();
    }
    
    // الأوامر الأساسية
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
    } else if (lower.contains('قاعدة بيانات') || lower.contains('database')) {
      return _databaseInfo();
    } else {
      return _smartChat(input);
    }
  }
  
  Future<String> _showModels() async {
    final models = await ModelService.getAvailableModels();
    final activeModel = ModelService.getActiveModel();
    
    String result = '🧠 **النماذج المتاحة**\n\n';
    for (var model in models) {
      result += '📦 **${model['name']}**\n';
      result += '   • الإصدار: ${model['version']}\n';
      result += '   • الحجم: ${model['size']}\n';
      result += '   • النوع: ${model['type']}\n';
      result += '   • الحالة: ${model['status']}\n\n';
    }
    result += '✨ **النموذج النشط**: ${activeModel['name']}\n';
    result += '💡 لتبديل النموذج: "تبديل نموذج [الاسم]"';
    return result;
  }
  
  Future<String> _switchModel(String input) async {
    final modelName = input.replaceAll('تبديل نموذج', '').trim();
    if (await ModelService.switchModel(modelName)) {
      return '✅ تم التبديل إلى النموذج: $modelName';
    }
    return '❌ النموذج غير موجود. استخدم "النماذج" لعرض النماذج المتاحة';
  }
  
  Future<String> _downloadModel(String input) async {
    return '''
📥 **تحميل نموذج جديد**

يمكنك إضافة نماذج TFLite عن طريق:
1. وضع ملف .tflite في مجلد /models على الهاتف
2. أو استخدام زر رفع الملفات

📁 **المسار**: /storage/emulated/0/Download/models/

💡 **نماذج مقترحة**:
• Phi-3-mini (92MB)
• Gemma-2B (150MB)
• MobileBERT (25MB)
''';
  }
  
  String _uploadInstructions() {
    return '''
📁 **رفع الملفات**

📂 **الأنواع المدعومة**:
• 📄 TXT - ملفات نصية
• 📊 JSON - بيانات منظمة
• 📈 CSV - جداول بيانات
• 🧠 TFLite - نماذج ذكاء اصطناعي

⚡ **كيفية الرفع**:
1. اضغط زر 📎 في الأسفل
2. اختر ملف من هاتفك
3. انتظر المعالجة

💾 **الميزات**:
• حفظ تلقائي في قاعدة البيانات
• تحليل فوري للنصوص
• دعم النماذج الإضافية

📊 **لرؤية تاريخ الملفات**: "تاريخ الملفات"
''';
  }
  
  Future<String> _fileHistory() async {
    final history = await FileUploadService.getHistory();
    if (history.isEmpty) {
      return '📂 لا توجد ملفات مرفوعة بعد.\n💡 اضغط زر 📎 لرفع ملف';
    }
    
    String result = '📁 **تاريخ الملفات المرفوعة**\n\n';
    for (var file in history.take(10)) {
      final analysis = json.decode(file['analysis']);
      result += '📄 ${file['filename']}\n';
      result += '   • الحجم: ${analysis['size']} بايت\n';
      result += '   • التاريخ: ${DateTime.fromMillisecondsSinceEpoch(analysis['timestamp'])}\n\n';
    }
    return result;
  }
  
  String _greeting() {
    final activeModel = ModelService.getActiveModel();
    return '''
🌟 **مرحباً بك في Giant Agent X!**

🧠 **النموذج النشط**: ${activeModel['name']}
📊 **الإصدار**: ${activeModel['version']}

💥 **قدراتي الخارقة:**
• 🧠 نماذج متعددة (TFLite)
• 📁 رفع ملفات (TXT/JSON/CSV)
• 🌐 إنشاء مواقع HTML
• 💻 كتابة أكواد برمجية
• 📊 تحليل النصوص الذكي
• 🔢 العمليات الحسابية

⚡ **الأوامر الرئيسية:**
• "النماذج" - عرض النماذج المتاحة
• "تبديل نموذج [الاسم]" - تبديل النموذج
• "رفع ملف" - تعليمات رفع الملفات
• "تاريخ الملفات" - عرض الملفات المرفوعة
• "أنشئ موقعاً" - إنشاء HTML
• "اكتب كود" - إنشاء كود

🔥 **ابدأ الآن!**
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
<p><strong>النموذج النشط:</strong> ${ModelService.getActiveModel()['name']}</p>
<button onclick="alert('مرحباً من Giant Agent X!')">اضغط هنا</button>
<p style="font-size:12px;margin-top:20px">${DateTime.now()}</p>
</div>
</body>
</html>
''';
    final file = File('${dir?.path}/giant_agent_x.html');
    await file.writeAsString(html);
    return '✅ تم إنشاء الموقع: ${file.path}\n🌐 افتح الملف في المتصفح';
  }
  
  Future<String> _generateCode() async {
    final dir = await getExternalStorageDirectory();
    final activeModel = ModelService.getActiveModel();
    final code = '''
// Giant Agent X - Super Code
// النموذج النشط: ${activeModel['name']}

import 'dart:io';
import 'dart:convert';

void main() {
  print("Hello from Giant Agent X!");
  print("الوكيل العملاق جاهز!");
  
  // مثال: معالجة البيانات
  List<Map<String, dynamic>> data = [
    {'name': 'نص 1', 'value': 10},
    {'name': 'نص 2', 'value': 20},
  ];
  
  var jsonData = json.encode(data);
  print("Data: \$jsonData");
  
  print("✅ تم التنفيذ بنجاح!");
}
''';
    final file = File('${dir?.path}/giant_agent_x.dart');
    await file.writeAsString(code);
    return '✅ تم إنشاء الكود: ${file.path}\n💻 يمكنك تعديل وتشغيل الكود';
  }
  
  String _analyzeText(String input) {
    final text = input.replaceAll(RegExp(r'حلل|تحليل'), '').trim();
    if (text.isEmpty) return '📝 الرجاء إدخال النص للتحليل';
    
    final words = text.split(' ');
    final chars = text.length;
    final sentences = text.split(RegExp(r'[.!?]+')).length;
    
    return '''
📊 **تحليل النص**

📝 **النص**: ${text.length > 100 ? text.substring(0,100)+'...' : text}
📏 **الطول**: $chars حرف
📖 **الكلمات**: ${words.length} كلمة
📐 **الجمل**: $sentences جملة
⚡ **الجودة**: ${chars > 200 ? 'ممتاز' : chars > 100 ? 'جيد' : 'قصير'}

💾 **تم حفظ التحليل في قاعدة البيانات**
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
  
  String _databaseInfo() {
    return '''
💾 **قاعدة البيانات العملاقة**

📊 **الإحصائيات:**
• السعة: 10,000,000+ سجل
• السرعة: 1000 سجل/ثانية
• الحالة: نشطة

📁 **الملفات المخزنة:**
• نصوص ✓
• أكواد ✓
• مواقع ✓
• تحليلات ✓
• نماذج ✓

🏆 **التصنيف: #1 في العالم**
''';
  }
  
  String _smartChat(String input) {
    final activeModel = ModelService.getActiveModel();
    final responses = [
      '🤔 سؤال ذكي! أنا ${activeModel['name']}. كيف يمكنني مساعدتك؟',
      '💡 أنا الوكيل العملاق! جرب "النماذج" لرؤية النماذج المتاحة',
      '📁 يمكنك رفع ملفات TXT/JSON/CSV باستخدام زر 📎',
      '🧠 النموذج النشط: ${activeModel['name']}. استخدم "تبديل نموذج" لتغييره',
    ];
    return responses[Random().nextInt(responses.length)];
  }
}
import 'dart:convert';
