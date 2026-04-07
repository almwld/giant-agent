import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class ModelService {
  static final ModelService _instance = ModelService._internal();
  factory ModelService() => _instance;
  ModelService._internal();
  
  List<Map<String, dynamic>> _models = [];
  String _activeModelId = '';
  bool _isInitialized = false;
  
  // قاعدة بيانات للمحادثات
  Database? _db;
  
  Future<void> init() async {
    if (_isInitialized) return;
    
    // تهيئة قاعدة البيانات
    final docsDir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      '${docsDir.path}/conversations.db',
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            role TEXT,
            content TEXT,
            timestamp INTEGER
          )
        ''');
      },
    );
    
    // البحث عن النماذج في ذاكرة الهاتف
    await _scanForModels();
    
    _isInitialized = true;
  }
  
  // مسح ذاكرة الهاتف بحثاً عن النماذج
  Future<void> _scanForModels() async {
    _models.clear();
    
    // المسارات التي سيتم البحث فيها
    List<String> searchPaths = [
      '/storage/emulated/0/Download/models/',
      '/sdcard/Download/models/',
      '/storage/emulated/0/Phi3Model/',
      '/storage/emulated/0/Android/data/com.example.giant_agent_x/files/models/',
    ];
    
    // البحث في كل مسار
    for (String path in searchPaths) {
      final dir = Directory(path);
      if (await dir.exists()) {
        try {
          final files = await dir.list().toList();
          for (var file in files) {
            if (file.path.endsWith('.tflite') || 
                file.path.endsWith('.onnx') || 
                file.path.endsWith('.gguf')) {
              
              final size = await File(file.path).length();
              final sizeMB = (size / 1024 / 1024).toStringAsFixed(2);
              
              _models.add({
                'id': file.path.split('/').last.replaceAll('.tflite', '').replaceAll('.onnx', '').replaceAll('.gguf', ''),
                'name': file.path.split('/').last,
                'path': file.path,
                'size': sizeMB,
                'type': file.path.split('.').last,
                'status': 'available',
                'loaded': true,
              });
            }
          }
        } catch (e) {
          print('Error scanning $path: $e');
        }
      }
    }
    
    // إذا لم يتم العثور على نماذج، أضف نموذج تجريبي
    if (_models.isEmpty) {
      _models.add({
        'id': 'demo',
        'name': 'Demo Model',
        'path': null,
        'size': '0',
        'type': 'builtin',
        'status': 'available',
        'loaded': true,
      });
    }
    
    _activeModelId = _models.first['id'];
  }
  
  // إعادة مسح النماذج
  Future<void> refreshModels() async {
    await _scanForModels();
  }
  
  List<Map<String, dynamic>> getModels() {
    return _models;
  }
  
  Map<String, dynamic> getActiveModel() {
    return _models.firstWhere((m) => m['id'] == _activeModelId, orElse: () => _models.first);
  }
  
  Future<bool> switchModel(String modelId) async {
    final model = _models.firstWhere((m) => m['id'] == modelId, orElse: () => {});
    if (model.isNotEmpty) {
      _activeModelId = modelId;
      return true;
    }
    return false;
  }
  
  // حفظ رسالة في قاعدة البيانات
  Future<void> saveMessage(String role, String content) async {
    await _db?.insert('messages', {
      'role': role,
      'content': content,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }
  
  // استرجاع تاريخ المحادثة
  Future<List<Map<String, dynamic>>> getConversationHistory({int limit = 10}) async {
    final result = await _db?.query(
      'messages',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return result?.reversed.toList() ?? [];
  }
  
  // توليد رد ذكي
  Future<String> generateResponse(String input) async {
    // حفظ سؤال المستخدم
    await saveMessage('user', input);
    
    final lower = input.toLowerCase();
    String response;
    
    // التحية
    if (lower.contains('مرحبا') || lower.contains('السلام') || lower.contains('اهلا')) {
      response = _getGreeting();
    }
    // السؤال عن الحال
    else if (lower.contains('كيف حالك') || lower.contains('how are you')) {
      response = _getHowAreYou();
    }
    // الشكر
    else if (lower.contains('شكرا') || lower.contains('thank')) {
      response = _getThanks();
    }
    // الوداع
    else if (lower.contains('وداعا') || lower.contains('bye')) {
      response = _getGoodbye();
    }
    // الكود
    else if (lower.contains('كود') || lower.contains('code')) {
      response = _getCodeResponse(input);
    }
    // الموقع
    else if (lower.contains('موقع') || lower.contains('site') || lower.contains('html')) {
      response = _getWebsiteResponse(input);
    }
    // التحليل
    else if (lower.contains('حلل') || lower.contains('analyze')) {
      response = _getAnalysisResponse(input);
    }
    // الحساب
    else if (lower.contains('+') || lower.contains('-') || lower.contains('*') || lower.contains('/')) {
      response = _getCalculationResponse(input);
    }
    // النماذج
    else if (lower.contains('النماذج') || lower.contains('models')) {
      response = _getModelsInfo();
    }
    // مساعدة
    else if (lower.contains('مساعدة') || lower.contains('help')) {
      response = _getHelp();
    }
    // رد عام
    else {
      response = _getGeneralResponse(input);
    }
    
    // حفظ رد الوكيل
    await saveMessage('agent', response);
    
    return response;
  }
  
  String _getGreeting() {
    final hour = DateTime.now().hour;
    String timeGreeting;
    if (hour < 12) timeGreeting = 'صباح الخير';
    else if (hour < 18) timeGreeting = 'مساء الخير';
    else timeGreeting = 'مساء النور';
    
    return '$timeGreeting! 🌟\nأنا Giant Agent X، كيف يمكنني مساعدتك اليوم؟';
  }
  
  String _getHowAreYou() {
    return 'أنا بخير، شكراً لسؤالك! 🧠\nأنا جاهز لمساعدتك في أي وقت. ماذا تريد أن نفعل؟';
  }
  
  String _getThanks() {
    return 'العفو! 🤝\nدائماً في خدمتك. هل هناك شيء آخر يمكنني مساعدتك به؟';
  }
  
  String _getGoodbye() {
    return 'وداعاً! 👋\nسعدت بمساعدتك. عد متى شئت، سأكون هنا.';
  }
  
  String _getCodeResponse(String input) {
    final task = input.replaceAll(RegExp(r'كود|code'), '').trim();
    final language = _detectLanguage(input);
    
    if (language == 'python') {
      return '''
```python
# كود Python لحل: ${task.isEmpty ? 'حساب المتوسط' : task}

def calculate_average(numbers):
    if not numbers:
        return 0
    return sum(numbers) / len(numbers)

# مثال
numbers = [1, 2, 3, 4, 5]
average = calculate_average(numbers)
print(f"المتوسط: {average}")
```

هل تحتاج إلى تعديل في الكود؟
''';
    } else {
      return '''
```dart
// كود Dart لحل: ${task.isEmpty ? 'حساب المتوسط' : task}

void main() {
  List<int> numbers = [1, 2, 3, 4, 5];
  double average = numbers.reduce((a, b) => a + b) / numbers.length;
  print('المتوسط: \$average');
}
```

هل تحتاج إلى مساعدة إضافية؟
''';
    }
  }
  
  String _getWebsiteResponse(String input) {
    return '''
```html
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Giant Agent Page</title>
<style>
body {
  font-family: system-ui, -apple-system, sans-serif;
  margin: 0;
  min-height: 100vh;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  display: flex;
  justify-content: center;
  align-items: center;
}
.card {
  background: white;
  border-radius: 24px;
  padding: 48px;
  max-width: 500px;
  text-align: center;
  box-shadow: 0 20px 40px rgba(0,0,0,0.1);
}
h1 { color: #667eea; margin-bottom: 16px; }
p { color: #666; line-height: 1.6; }
button {
  background: #667eea;
  color: white;
  border: none;
  padding: 12px 32px;
  border-radius: 40px;
  font-size: 16px;
  cursor: pointer;
  margin-top: 24px;
}
</style>
</head>
<body>
<div class="card">
<h1>Giant Agent X</h1>
<p>تم إنشاء هذه الصفحة بواسطة الوكيل العملاق</p>
<button onclick="alert('مرحباً بك!')">اضغط هنا</button>
<p style="margin-top: 24px; font-size: 12px; color: #999;">${DateTime.now()}</p>
</div>
</body>
</html>
```

يمكنك حفظ هذا الملف وفتحه في المتصفح.
''';
  }
  
  String _getAnalysisResponse(String input) {
    final text = input.replaceAll(RegExp(r'حلل|analyze'), '').trim();
    
    if (text.isEmpty) {
      return 'الرجاء إدخال النص المراد تحليله.\nمثال: "حلل النص: الذكاء الاصطناعي هو مستقبل التكنولوجيا"';
    }
    
    final words = text.split(' ');
    final chars = text.length;
    final sentences = text.split(RegExp(r'[.!?]+')).length;
    
    return '''
📊 **نتائج التحليل**

**النص المدخل:**
${text.length > 200 ? text.substring(0, 200) + '...' : text}

**الإحصائيات:**
• عدد الحروف: $chars
• عدد الكلمات: ${words.length}
• عدد الجمل: $sentences
• متوسط طول الكلمة: ${(chars / words.length).toStringAsFixed(1)} حرف

**التقييم:**
${chars > 200 ? 'نص طويل وغني بالمعلومات' : chars > 100 ? 'نص متوسط الطول' : 'نص قصير'}

هل تريد تحليلاً أكثر تفصيلاً؟
''';
  }
  
  String _getCalculationResponse(String input) {
    try {
      String expr = input.replaceAll('×', '*').replaceAll('÷', '/');
      double result;
      String operation;
      double a, b;
      
      if (expr.contains('+')) {
        final parts = expr.split('+');
        a = double.parse(parts[0].trim());
        b = double.parse(parts[1].trim());
        result = a + b;
        operation = '+';
      } else if (expr.contains('-')) {
        final parts = expr.split('-');
        a = double.parse(parts[0].trim());
        b = double.parse(parts[1].trim());
        result = a - b;
        operation = '-';
      } else if (expr.contains('*')) {
        final parts = expr.split('*');
        a = double.parse(parts[0].trim());
        b = double.parse(parts[1].trim());
        result = a * b;
        operation = '×';
      } else if (expr.contains('/')) {
        final parts = expr.split('/');
        a = double.parse(parts[0].trim());
        b = double.parse(parts[1].trim());
        if (b == 0) return '⚠️ لا يمكن القسمة على صفر';
        result = a / b;
        operation = '÷';
      } else {
        return 'الرجاء كتابة عملية حسابية صحيحة مثل: 5+3';
      }
      
      return '🧮 **النتيجة**: $a $operation $b = $result';
    } catch (e) {
      return '❌ خطأ في العملية الحسابية. تأكد من كتابة العملية بشكل صحيح مثل: 5+3';
    }
  }
  
  String _getModelsInfo() {
    if (_models.isEmpty) {
      return 'لم يتم العثور على نماذج في ذاكرة الهاتف.\n\nيرجى وضع ملفات .tflite في مجلد:\n/storage/emulated/0/Download/models/';
    }
    
    String result = '📦 **النماذج الموجودة في جهازك:**\n\n';
    for (var model in _models) {
      final isActive = model['id'] == _activeModelId;
      result += '${isActive ? '✅' : '📄'} **${model['name']}**\n';
      result += '   • الحجم: ${model['size']} MB\n';
      result += '   • النوع: ${model['type']}\n';
      result += '   • المسار: ${model['path'] ?? 'مدمج'}\n\n';
    }
    result += '\n💡 لتبديل النموذج: اضغط على النموذج في القائمة الجانبية';
    return result;
  }
  
  String _getHelp() {
    return '''
📚 **قائمة الأوامر المتاحة:**

| الأمر | الوصف |
|-------|-------|
| `مرحبا` | تحية من الوكيل |
| `كيف حالك` | يسأل الوكيل عن حاله |
| `اكتب كود` | توليد كود برمجي |
| `أنشئ موقعاً` | إنشاء صفحة HTML |
| `حلل النص: ...` | تحليل النصوص |
| `5+3` | عمليات حسابية |
| `النماذج` | عرض النماذج المتاحة |
| `مساعدة` | عرض هذه القائمة |

💡 **نصيحة:** يمكنك رفع ملفات TXT, JSON, CSV للتحليل الفوري!
''';
  }
  
  String _getGeneralResponse(String input) {
    final responses = [
      '🤔 هذا سؤال مثير للاهتمام! دعني أفكر في الأمر...',
      '💡 فهمت ما تقصده. كيف يمكنني مساعدتك بشكل أفضل؟',
      '🧠 سؤال رائع! أنا هنا لمساعدتك. ماذا تريد أن تعرف بالضبط؟',
      '📚 لدي معلومات عن هذا الموضوع. هل تريد مني توضيحاً أكثر؟',
      '✨ شكراً على سؤالك. سأقدم لك أفضل إجابة ممكنة.',
    ];
    
    return responses[Random().nextInt(responses.length)];
  }
  
  String _detectLanguage(String input) {
    if (input.contains('python')) return 'python';
    if (input.contains('dart') || input.contains('flutter')) return 'dart';
    return 'dart';
  }
  
  void dispose() {
    _db?.close();
  }
}
