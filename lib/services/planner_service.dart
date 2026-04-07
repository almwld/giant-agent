class PlannerService {
  static final PlannerService _instance = PlannerService._internal();
  factory PlannerService() => _instance;
  PlannerService._internal();
  
  List<Map<String, dynamic>> _plan = [];
  
  Future<List<Map<String, dynamic>>> createPlan(String goal) async {
    _plan.clear();
    
    // تقسيم الهدف إلى خطوات
    final steps = _breakDownGoal(goal);
    
    for (var i = 0; i < steps.length; i++) {
      _plan.add({
        'step': i + 1,
        'action': steps[i],
        'status': 'pending',
      });
    }
    
    return _plan;
  }
  
  List<String> _breakDownGoal(String goal) {
    final lower = goal.toLowerCase();
    
    if (lower.contains('موقع') || lower.contains('html')) {
      return [
        'تحليل متطلبات الموقع',
        'تصميم هيكل الموقع',
        'كتابة كود HTML',
        'إضافة تنسيق CSS',
        'اختبار الموقع',
        'حفظ الموقع',
      ];
    } else if (lower.contains('كود') || lower.contains('برنامج')) {
      return [
        'فهم متطلبات البرنامج',
        'تصميم الخوارزمية',
        'كتابة الكود',
        'اختبار الكود',
        'تحسين الأداء',
      ];
    } else if (lower.contains('تحليل') || lower.contains('data')) {
      return [
        'جمع البيانات',
        'تنظيف البيانات',
        'تحليل البيانات',
        'استخراج النتائج',
        'توليد التقرير',
      ];
    }
    
    return [
      'فهم المهمة',
      'تخطيط الخطوات',
      'تنفيذ المهمة',
      'مراجعة النتائج',
      'تقديم الناتج',
    ];
  }
  
  String getNextAction() {
    for (var step in _plan) {
      if (step['status'] == 'pending') {
        step['status'] = 'in_progress';
        return step['action'];
      }
    }
    return 'completed';
  }
  
  void markStepComplete(int stepNumber) {
    for (var step in _plan) {
      if (step['step'] == stepNumber) {
        step['status'] = 'completed';
        break;
      }
    }
  }
  
  bool isPlanComplete() {
    return _plan.every((step) => step['status'] == 'completed');
  }
  
  String getProgress() {
    final completed = _plan.where((s) => s['status'] == 'completed').length;
    final total = _plan.length;
    return 'تقدم: $completed/$total خطوة (${(completed / total * 100).toStringAsFixed(0)}%)';
  }
}
