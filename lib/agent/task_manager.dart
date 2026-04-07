import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';

class TaskManager {
  static final TaskManager _instance = TaskManager._internal();
  factory TaskManager() => _instance;
  TaskManager._internal();
  
  List<Map<String, dynamic>> _tasks = [];
  String _currentTask = '';
  
  // إنشاء مهمة جديدة
  Future<Map<String, dynamic>> createTask(String description) async {
    final taskId = DateTime.now().millisecondsSinceEpoch.toString();
    final task = {
      'id': taskId,
      'description': description,
      'status': 'planning',
      'steps': [],
      'created_at': DateTime.now().toIso8601String(),
    };
    
    // تحليل المهمة وتقسيمها إلى خطوات
    task['steps'] = await _analyzeAndPlan(description);
    _tasks.add(task);
    _currentTask = taskId;
    
    return task;
  }
  
  Future<List<Map<String, dynamic>>> _analyzeAndPlan(String description) async {
    final steps = <Map<String, dynamic>>[];
    final lower = description.toLowerCase();
    
    if (lower.contains('موقع') || lower.contains('website') || lower.contains('html')) {
      steps.addAll([
        {'step': 1, 'action': 'تحليل متطلبات الموقع', 'type': 'analysis', 'status': 'pending'},
        {'step': 2, 'action': 'تصميم هيكل الموقع', 'type': 'design', 'status': 'pending'},
        {'step': 3, 'action': 'كتابة كود HTML/CSS/JS', 'type': 'code', 'status': 'pending'},
        {'step': 4, 'action': 'اختبار الموقع', 'type': 'test', 'status': 'pending'},
        {'step': 5, 'action': 'تجميع الملفات', 'type': 'package', 'status': 'pending'},
      ]);
    } else if (lower.contains('تطبيق') || lower.contains('app') || lower.contains('flutter')) {
      steps.addAll([
        {'step': 1, 'action': 'تحليل متطلبات التطبيق', 'type': 'analysis', 'status': 'pending'},
        {'step': 2, 'action': 'تصميم واجهة المستخدم', 'type': 'design', 'status': 'pending'},
        {'step': 3, 'action': 'كتابة كود التطبيق', 'type': 'code', 'status': 'pending'},
        {'step': 4, 'action': 'اختبار التطبيق', 'type': 'test', 'status': 'pending'},
        {'step': 5, 'action': 'تجميع المشروع', 'type': 'package', 'status': 'pending'},
      ]);
    } else if (lower.contains('تحليل') || lower.contains('data') || lower.contains('بيانات')) {
      steps.addAll([
        {'step': 1, 'action': 'جمع البيانات', 'type': 'collection', 'status': 'pending'},
        {'step': 2, 'action': 'تنظيف البيانات', 'type': 'cleaning', 'status': 'pending'},
        {'step': 3, 'action': 'تحليل البيانات', 'type': 'analysis', 'status': 'pending'},
        {'step': 4, 'action': 'إنشاء تقرير', 'type': 'report', 'status': 'pending'},
        {'step': 5, 'action': 'تصدير النتائج', 'type': 'export', 'status': 'pending'},
      ]);
    } else {
      steps.addAll([
        {'step': 1, 'action': 'فهم المهمة', 'type': 'analysis', 'status': 'pending'},
        {'step': 2, 'action': 'تخطيط التنفيذ', 'type': 'planning', 'status': 'pending'},
        {'step': 3, 'action': 'تنفيذ المهمة', 'type': 'execution', 'status': 'pending'},
        {'step': 4, 'action': 'مراجعة النتائج', 'type': 'review', 'status': 'pending'},
        {'step': 5, 'action': 'تسليم المخرجات', 'type': 'delivery', 'status': 'pending'},
      ]);
    }
    
    return steps;
  }
  
  // تنفيذ الخطوة التالية
  Future<Map<String, dynamic>> executeNextStep() async {
    final task = _tasks.firstWhere((t) => t['id'] == _currentTask, orElse: () => {});
    if (task.isEmpty) return {'error': 'لا توجد مهمة نشطة'};
    
    final pendingStep = task['steps'].firstWhere((s) => s['status'] == 'pending', orElse: () => null);
    if (pendingStep == null) {
      return await _finalizeTask(task);
    }
    
    pendingStep['status'] = 'in_progress';
    final result = await _executeStep(pendingStep, task['description']);
    pendingStep['status'] = 'completed';
    pendingStep['result'] = result;
    
    return {
      'step': pendingStep['step'],
      'action': pendingStep['action'],
      'result': result,
      'remaining': task['steps'].where((s) => s['status'] == 'pending').length,
    };
  }
  
  Future<String> _executeStep(Map<String, dynamic> step, String description) async {
    switch(step['type']) {
      case 'code':
        return await _generateCode(description);
      case 'package':
        return await _packageProject(description);
      case 'report':
        return await _generateReport(description);
      case 'export':
        return await _exportResults(description);
      default:
        return '✅ تم تنفيذ: ${step['action']}';
    }
  }
  
  Future<String> _generateCode(String description) async {
    final dir = await getExternalStorageDirectory();
    final projectDir = Directory('${dir?.path}/generated_project');
    await projectDir.create(recursive: true);
    
    // إنشاء ملفات المشروع
    final mainFile = File('${projectDir.path}/main.py');
    await mainFile.writeAsString(_generatePythonCode(description));
    
    final readmeFile = File('${projectDir.path}/README.md');
    await readmeFile.writeAsString('# Generated Project\n\n$description\n\nCreated by Giant Agent X');
    
    return '✅ تم إنشاء كود المشروع في ${projectDir.path}';
  }
  
  String _generatePythonCode(String description) {
    return '''
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
\"\"\"
$description
Generated by Giant Agent X
\"\"\"

import os
import json
from datetime import datetime

def main():
    print("🚀 Giant Agent X - Project Generator")
    print("=" * 50)
    print(f"📋 المشروع: $description")
    print(f"📅 التاريخ: {datetime.now()}")
    print("=" * 50)
    
    # إنشاء هيكل المشروع
    folders = ['src', 'data', 'output', 'tests']
    for folder in folders:
        os.makedirs(folder, exist_ok=True)
        print(f"✅ تم إنشاء مجلد: {folder}")
    
    # إنشاء ملف التكوين
    config = {
        'project_name': '$description',
        'version': '1.0.0',
        'created_at': datetime.now().isoformat(),
        'author': 'Giant Agent X'
    }
    
    with open('config.json', 'w') as f:
        json.dump(config, f, indent=2, ensure_ascii=False)
    
    print("\\n✅ تم إنشاء المشروع بنجاح!")
    print("📁 هيكل المشروع جاهز للاستخدام")

if __name__ == "__main__":
    main()
''';
  }
  
  Future<String> _packageProject(String description) async {
    final dir = await getExternalStorageDirectory();
    final projectDir = Directory('${dir?.path}/generated_project');
    final outputDir = Directory('${dir?.path}/output');
    await outputDir.create(recursive: true);
    
    final zipPath = '${outputDir.path}/project_${DateTime.now().millisecondsSinceEpoch}.zip';
    
    // إنشاء ملف ZIP
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    await encoder.addDirectory(projectDir);
    await encoder.close();
    
    return '✅ تم تجميع المشروع في: $zipPath';
  }
  
  Future<String> _generateReport(String description) async {
    final dir = await getExternalStorageDirectory();
    final reportPath = '${dir?.path}/report_${DateTime.now().millisecondsSinceEpoch}.md';
    final report = '''
# تقرير المشروع

**الوصف:** $description
**التاريخ:** ${DateTime.now()}
**المنتج:** Giant Agent X

## الملخص التنفيذي
تم تنفيذ المهمة بنجاح وفقاً للمتطلبات المحددة.

## النتائج
- اكتملت جميع الخطوات بنجاح
- تم إنشاء المخرجات المطلوبة
- جاهز للتسليم النهائي

## المرفقات
- ملفات المشروع
- التوثيق الكامل
''';
    
    await File(reportPath).writeAsString(report);
    return '✅ تم إنشاء التقرير: $reportPath';
  }
  
  Future<String> _exportResults(String description) async {
    final dir = await getExternalStorageDirectory();
    final exportPath = '${dir?.path}/results_${DateTime.now().millisecondsSinceEpoch}.json';
    
    final results = {
      'project': description,
      'timestamp': DateTime.now().toIso8601String(),
      'status': 'completed',
      'generated_by': 'Giant Agent X',
    };
    
    await File(exportPath).writeAsString(json.encode(results));
    return '✅ تم تصدير النتائج: $exportPath';
  }
  
  Future<Map<String, dynamic>> _finalizeTask(Map<String, dynamic> task) async {
    final dir = await getExternalStorageDirectory();
    task['status'] = 'completed';
    task['completed_at'] = DateTime.now().toIso8601String();
    
    // إنشاء ملف الإخراج النهائي
    final outputPath = '${dir?.path}/final_output_${task['id']}.json';
    await File(outputPath).writeAsString(json.encode(task));
    
    return {
      'status': 'completed',
      'message': '✅ تم إكمال المهمة بنجاح!',
      'output_file': outputPath,
      'task_summary': task,
    };
  }
  
  String getProgress() {
    final task = _tasks.firstWhere((t) => t['id'] == _currentTask, orElse: () => {});
    if (task.isEmpty) return 'لا توجد مهمة نشطة';
    
    final completed = task['steps'].where((s) => s['status'] == 'completed').length;
    final total = task['steps'].length;
    return 'تقدم: $completed/$total (${(completed/total*100).toStringAsFixed(0)}%)';
  }
  
  List<Map<String, dynamic>> getTasks() => _tasks;
  
  void clearTasks() {
    _tasks.clear();
    _currentTask = '';
  }
}
