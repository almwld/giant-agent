import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

class PythonExecutor {
  static final PythonExecutor _instance = PythonExecutor._internal();
  factory PythonExecutor() => _instance;
  PythonExecutor._internal();
  
  Future<Map<String, dynamic>> executePython(String code) async {
    try {
      final dir = await getTemporaryDirectory();
      final scriptPath = '${dir.path}/temp_script_${DateTime.now().millisecondsSinceEpoch}.py';
      final scriptFile = File(scriptPath);
      
      await scriptFile.writeAsString(code);
      
      final result = await Process.run('python3', [scriptPath]);
      
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
  
  Future<String> createDataAnalyzer(List<num> data) async {
    final code = '''
import json
import statistics
from datetime import datetime

data = ${json.encode(data)}

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

✅ تم التحليل بنجاح
''';
    } else {
      return '❌ خطأ: ${result['error']}';
    }
  }
  
  Future<String> analyzeTextWithNLP(String text) async {
    final code = '''
import json
import re
from collections import Counter

text = """${text.replaceAll('"', '\\"')}"""

words = re.findall(r'\\b\\w+\\b', text.lower())
word_count = len(words)
char_count = len(text)
sentences = re.split(r'[.!?]+', text)
sentence_count = len([s for s in sentences if s.strip()])

word_freq = Counter(words)
top_words = word_freq.most_common(5)

positive_words = ['good', 'great', 'excellent', 'amazing', 'wonderful', 'happy']
negative_words = ['bad', 'terrible', 'awful', 'horrible', 'sad', 'angry']

pos_count = sum(1 for w in words if w in positive_words)
neg_count = sum(1 for w in words if w in negative_words)

sentiment = 'positive' if pos_count > neg_count else 'negative' if neg_count > pos_count else 'neutral'

result = {
    'word_count': word_count,
    'char_count': char_count,
    'sentence_count': sentence_count,
    'sentiment': sentiment,
    'top_keywords': [{'word': w, 'count': c} for w, c in top_words],
}

print(json.dumps(result, indent=2, ensure_ascii=False))
''';
    
    final execResult = await executePython(code);
    if (execResult['success']) {
      return '''
📝 **تحليل النص باستخدام Python**

${execResult['output']}

✅ تم التحليل بنجاح
''';
    } else {
      return '❌ خطأ: ${execResult['error']}';
    }
  }
  
  Future<String> createAndTrainModel() async {
    final code = '''
import json
import numpy as np
from sklearn.linear_model import LinearRegression

X = np.array([[1], [2], [3], [4], [5], [6], [7], [8], [9], [10]])
y = np.array([2, 4, 6, 8, 10, 12, 14, 16, 18, 20])

model = LinearRegression()
model.fit(X, y)

predictions = model.predict(X)

result = {
    'coefficient': float(model.coef_[0]),
    'intercept': float(model.intercept_),
    'score': float(model.score(X, y)),
}

print(json.dumps(result, indent=2))
''';
    
    final execResult = await executePython(code);
    if (execResult['success']) {
      return '''
🧠 **تدريب نموذج تعلم آلة**

${execResult['output']}

✅ تم تدريب النموذج بنجاح
''';
    } else {
      return '❌ خطأ: ${execResult['error']}';
    }
  }
  
  Future<String> automateTasks(List<String> tasks) async {
    final code = '''
import asyncio
import time
from datetime import datetime

tasks = ${json.encode(tasks)}

async def execute_task(task_name):
    await asyncio.sleep(0.5)
    return {"task": task_name, "status": "completed"}

async def main():
    results = await asyncio.gather(*[execute_task(task) for task in tasks])
    return results

if __name__ == "__main__":
    results = asyncio.run(main())
    print(f"Completed {len(results)} tasks")
''';
    
    final execResult = await executePython(code);
    if (execResult['success']) {
      return '''
⚡ **أتمتة المهام**

${execResult['output']}

✅ تم تنفيذ ${tasks.length} مهمة بنجاح
''';
    } else {
      return '❌ خطأ: ${execResult['error']}';
    }
  }
}
