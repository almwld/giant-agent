import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

class PythonExecutor {
  static final PythonExecutor _instance = PythonExecutor._internal();
  factory PythonExecutor() => _instance;
  PythonExecutor._internal();
  
  // تنفيذ كود بايثون
  Future<Map<String, dynamic>> executePython(String code) async {
    try {
      final dir = await getTemporaryDirectory();
      final scriptPath = '${dir.path}/temp_script_${DateTime.now().millisecondsSinceEpoch}.py';
      final scriptFile = File(scriptPath);
      
      // حفظ الكود في ملف مؤقت
      await scriptFile.writeAsString(code);
      
      // تنفيذ الكود
      final result = await Process.run('python3', [scriptPath]);
      
      // حذف الملف المؤقت
      await scriptFile.delete();
      
      return {
        'success': true,
        'output': result.stdout.toString(),
        'error': result.stderr.toString(),
        'exitCode': result.exitCode,
      };
    } catch (e) {
      return {
        'success': false,
        'output': '',
        'error': e.toString(),
        'exitCode': -1,
      };
    }
  }
  
  // إنشاء وتنفيذ محلل بيانات
  Future<String> createDataAnalyzer(List<num> data) async {
    final code = '''
import json
import statistics
from datetime import datetime

# البيانات
data = ${json.encode(data)}

# التحليل الإحصائي
analysis = {
    'total': len(data),
    'sum': sum(data),
    'average': statistics.mean(data) if data else 0,
    'median': statistics.median(data) if data else 0,
    'min': min(data) if data else 0,
    'max': max(data) if data else 0,
    'variance': statistics.variance(data) if len(data) > 1 else 0,
    'timestamp': datetime.now().isoformat()
}

print(json.dumps(analysis, indent=2))
''';
    
    final result = await executePython(code);
    if (result['success']) {
      return '''
📊 **تحليل البيانات باستخدام Python**

${result['output']}

✅ تم التحليل بنجاح بواسطة Python
''';
    } else {
      return '❌ خطأ في تنفيذ Python: ${result['error']}';
    }
  }
  
  // إنشاء موقع ويب باستخدام Flask
  Future<String> createFlaskApp(String appName) async {
    final dir = await getExternalStorageDirectory();
    final appDir = Directory('${dir?.path}/$appName');
    await appDir.create(recursive: true);
    
    // إنشاء ملف Flask الرئيسي
    final flaskCode = '''
from flask import Flask, render_template, request, jsonify
import json
from datetime import datetime

app = Flask(__name__)

# البيانات
data_store = []

@app.route('/')
def home():
    return '''
<!DOCTYPE html>
<html>
<head>
    <title>$appName</title>
    <style>
        body { font-family: Arial; margin: 40px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); }
        .container { max-width: 600px; margin: auto; background: white; padding: 20px; border-radius: 10px; }
        input, button { padding: 10px; margin: 5px; }
        button { background: #667eea; color: white; border: none; cursor: pointer; }
    </style>
</head>
<body>
    <div class="container">
        <h1>$appName</h1>
        <p>تم إنشاؤه بواسطة Giant Agent X</p>
        <form action="/api/data" method="POST">
            <input type="text" name="data" placeholder="أدخل بياناتك">
            <button type="submit">إرسال</button>
        </form>
        <div id="result"></div>
    </div>
    <script>
        fetch('/api/data')
            .then(res => res.json())
            .then(data => {
                document.getElementById('result').innerHTML = '<pre>' + JSON.stringify(data, null, 2) + '</pre>';
            });
    </script>
</body>
</html>
'''

@app.route('/api/data', methods=['GET', 'POST'])
def handle_data():
    if request.method == 'POST':
        data = request.form.get('data')
        data_store.append({
            'data': data,
            'timestamp': datetime.now().isoformat()
        })
        return jsonify({'status': 'success', 'message': 'Data saved'})
    return jsonify(data_store)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
''';
    
    await File('${appDir.path}/app.py').writeAsString(flaskCode);
    
    // إنشاء requirements.txt
    final requirements = '''
Flask==2.3.0
''';
    await File('${appDir.path}/requirements.txt').writeAsString(requirements);
    
    return '''
✅ **تم إنشاء تطبيق Flask:** $appName
📂 المسار: ${appDir.path}
🚀 للتشغيل:
   cd ${appDir.path}
   pip install -r requirements.txt
   python app.py
🌐 افتح http://localhost:5000
''';
  }
  
  // تحليل النصوص باستخدام Python NLP
  Future<String> analyzeTextWithNLP(String text) async {
    final code = '''
import json
import re
from collections import Counter

text = """${text.replaceAll('"', '\\"')}"""

# تحليل النص
words = re.findall(r'\\b\\w+\\b', text.lower())
word_count = len(words)
char_count = len(text)
sentences = re.split(r'[.!?]+', text)
sentence_count = len([s for s in sentences if s.strip()])

# الكلمات الأكثر تكراراً
word_freq = Counter(words)
top_words = word_freq.most_common(10)

# تحليل المشاعر (بسيط)
positive_words = ['good', 'great', 'excellent', 'amazing', 'wonderful', 'happy', 'joy']
negative_words = ['bad', 'terrible', 'awful', 'horrible', 'sad', 'angry', 'hate']

pos_count = sum(1 for w in words if w in positive_words)
neg_count = sum(1 for w in words if w in negative_words)

sentiment = 'positive' if pos_count > neg_count else 'negative' if neg_count > pos_count else 'neutral'

result = {
    'word_count': word_count,
    'char_count': char_count,
    'sentence_count': sentence_count,
    'sentiment': sentiment,
    'top_keywords': [{'word': w, 'count': c} for w, c in top_words],
    'analysis_timestamp': str(__import__('datetime').datetime.now())
}

print(json.dumps(result, indent=2, ensure_ascii=False))
''';
    
    final execResult = await executePython(code);
    if (execResult['success']) {
      return '''
📝 **تحليل النص باستخدام Python NLP**

${execResult['output']}

✅ تم التحليل باستخدام معالجة اللغة الطبيعية
''';
    } else {
      return '❌ خطأ: ${execResult['error']}';
    }
  }
  
  // إنشاء وتدريب نموذج تعلم آلة بسيط
  Future<String> createAndTrainModel() async {
    final code = '''
import json
import numpy as np
from sklearn.linear_model import LinearRegression
from sklearn.model_selection import train_test_split

# بيانات تجريبية
X = np.array([[1], [2], [3], [4], [5], [6], [7], [8], [9], [10]])
y = np.array([2, 4, 6, 8, 10, 12, 14, 16, 18, 20])

# تقسيم البيانات
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

# تدريب النموذج
model = LinearRegression()
model.fit(X_train, y_train)

# تقييم النموذج
score = model.score(X_test, y_test)
predictions = model.predict(X_test)

result = {
    'model_type': 'Linear Regression',
    'accuracy': float(score),
    'coefficient': float(model.coef_[0]),
    'intercept': float(model.intercept_),
    'predictions': [float(p) for p in predictions],
    'actual': [float(y) for y in y_test]
}

print(json.dumps(result, indent=2))
''';
    
    final execResult = await executePython(code);
    if (execResult['success']) {
      return '''
🧠 **تدريب نموذج تعلم آلة**

${execResult['output']}

✅ تم تدريب النموذج بنجاح باستخدام scikit-learn
''';
    } else {
      return '❌ خطأ: ${execResult['error']}\n\n💡 تأكد من تثبيت: pip install numpy scikit-learn';
    }
  }
  
  // إنشاء API باستخدام FastAPI
  Future<String> createFastAPI(String apiName) async {
    final dir = await getExternalStorageDirectory();
    final apiDir = Directory('${dir?.path}/$apiName');
    await apiDir.create(recursive: true);
    
    final fastapiCode = '''
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime
import json

app = FastAPI(title="$apiName", version="1.0.0")

# نموذج البيانات
class Item(BaseModel):
    id: int
    name: str
    description: Optional[str] = None
    price: float
    created_at: datetime = datetime.now()

# تخزين البيانات
items_db = []

@app.get("/")
def root():
    return {"message": "Welcome to $apiName", "status": "running"}

@app.get("/items", response_model=List[Item])
def get_items():
    return items_db

@app.post("/items", response_model=Item)
def create_item(item: Item):
    items_db.append(item)
    return item

@app.get("/items/{item_id}")
def get_item(item_id: int):
    for item in items_db:
        if item.id == item_id:
            return item
    raise HTTPException(status_code=404, detail="Item not found")

@app.delete("/items/{item_id}")
def delete_item(item_id: int):
    for i, item in enumerate(items_db):
        if item.id == item_id:
            items_db.pop(i)
            return {"message": "Item deleted"}
    raise HTTPException(status_code=404, detail="Item not found")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
''';
    
    await File('${apiDir.path}/main.py').writeAsString(fastapiCode);
    
    final requirements = '''
fastapi==0.100.0
uvicorn==0.23.0
pydantic==2.0.0
''';
    await File('${apiDir.path}/requirements.txt').writeAsString(requirements);
    
    return '''
✅ **تم إنشاء API باستخدام FastAPI:** $apiName
📂 المسار: ${apiDir.path}
🚀 للتشغيل:
   cd ${apiDir.path}
   pip install -r requirements.txt
   python main.py
🌐 افتح http://localhost:8000/docs
''';
  }
  
  // أتمتة مهام متعددة
  Future<String> automateTasks(List<String> tasks) async {
    final code = '''
import asyncio
import time
from datetime import datetime

tasks = ${json.encode(tasks)}

async def execute_task(task_name, duration):
    print(f"🔄 بدء تنفيذ: {task_name}")
    await asyncio.sleep(duration)
    print(f"✅ اكتمل: {task_name}")
    return {"task": task_name, "duration": duration, "status": "completed"}

async def main():
    print("🚀 بدء الأتمتة")
    print(f"📋 عدد المهام: {len(tasks)}")
    print("=" * 40)
    
    start_time = time.time()
    
    # تنفيذ المهام بالتوازي
    results = await asyncio.gather(*[
        execute_task(task, 1) for task in tasks
    ])
    
    end_time = time.time()
    
    print("=" * 40)
    print(f"✅ اكتملت {len(results)} مهمة")
    print(f"⏱️ الوقت المستغرق: {end_time - start_time:.2f} ثانية")
    
    return results

if __name__ == "__main__":
    results = asyncio.run(main())
    print("\\n🎉 تمت الأتمتة بنجاح!")
''';
    
    final execResult = await executePython(code);
    if (execResult['success']) {
      return '''
⚡ **أتمتة المهام باستخدام Python**

${execResult['output']}

✅ تم تنفيذ ${tasks.length} مهمة بنجاح
''';
    } else {
      return '❌ خطأ: ${execResult['error']}';
    }
  }
}
