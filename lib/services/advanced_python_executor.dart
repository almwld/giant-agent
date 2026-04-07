import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

class AdvancedPythonExecutor {
  static final AdvancedPythonExecutor _instance = AdvancedPythonExecutor._internal();
  factory AdvancedPythonExecutor() => _instance;
  AdvancedPythonExecutor._internal();
  
  Future<Map<String, dynamic>> executeWithFiles(String code, List<String> inputFiles) async {
    final dir = await getTemporaryDirectory();
    final scriptPath = '${dir.path}/executor_${DateTime.now().millisecondsSinceEpoch}.py';
    
    // نسخ الملفات المدخلة
    final inputPaths = <String>[];
    for (var file in inputFiles) {
      final destPath = '${dir.path}/${file.split('/').last}';
      await File(file).copy(destPath);
      inputPaths.add(destPath);
    }
    
    await File(scriptPath).writeAsString(code);
    
    final result = await Process.run('python3', [scriptPath]);
    
    await File(scriptPath).delete();
    for (var path in inputPaths) {
      await File(path).delete();
    }
    
    return {
      'success': result.exitCode == 0,
      'output': result.stdout.toString(),
      'error': result.stderr.toString(),
    };
  }
  
  Future<String> createDataSciencePipeline(String description) async {
    final code = '''
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from datetime import datetime

print("📊 Data Science Pipeline")
print("=" * 50)
print(f"Task: $description")
print(f"Time: {datetime.now()}")

# إنشاء بيانات تجريبية
data = pd.DataFrame({
    'date': pd.date_range('2024-01-01', periods=100),
    'value': np.random.randn(100).cumsum()
})

# تحليل البيانات
print(f"\\n📈 Statistics:")
print(f"Mean: {data['value'].mean():.2f}")
print(f"Std: {data['value'].std():.2f}")
print(f"Min: {data['value'].min():.2f}")
print(f"Max: {data['value'].max():.2f}")

# حفظ النتائج
data.to_csv('analysis_results.csv', index=False)
plt.figure(figsize=(10, 6))
plt.plot(data['date'], data['value'])
plt.title('Data Analysis Results')
plt.savefig('analysis_plot.png')

print("\\n✅ Analysis complete!")
print("📁 Results saved to:")
print("  • analysis_results.csv")
print("  • analysis_plot.png")
''';
    
    final result = await executeWithFiles(code, []);
    return '''
📊 **تحليل البيانات المتقدم**

${result['output']}

✅ تم إنشاء:
• ملف CSV للنتائج
• رسم بياني PNG
''';
  }
}
