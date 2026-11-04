import 'agent_service.dart';

/// Model-driven task planner. It asks the active local model for a plan and
/// keeps planning separate from execution; a step is not completed until the
/// caller explicitly reports its real result.
class PlannerService {
  PlannerService._internal();
  static final PlannerService _instance = PlannerService._internal();
  factory PlannerService() => _instance;

  final AgentService _agent = AgentService.instance;
  final List<Map<String, dynamic>> _plan = [];

  Future<List<Map<String, dynamic>>> createPlan(String goal) async {
    final normalized = goal.trim();
    if (normalized.isEmpty) throw ArgumentError.value(goal, 'goal');
    final answer = await _agent.runTask(
      'أنشئ خطة تنفيذ عملية للهدف التالي فقط، ولا تنفذ أي أدوات أو تغييرات. '
      'أخرج قائمة مرقمة من 3 إلى 8 خطوات، خطوة واحدة في كل سطر، '
      'واجعل الخطوات قابلة للتحقق ولا تفترض موارد غير متاحة.\nالهدف: $normalized',
    );
    final parsed = answer
        .split('\n')
        .map((line) => line.trim())
        .where((line) => RegExp(r'^(?:[-*•]|\d+[.)、])\s*').hasMatch(line))
        .map((line) => line.replaceFirst(RegExp(r'^(?:[-*•]|\d+[.)、])\s*'), '').trim())
        .where((line) => line.isNotEmpty)
        .take(8)
        .toList();
    if (parsed.isEmpty) {
      throw StateError('لم يتمكن النموذج من إنتاج خطة قابلة للقراءة: $answer');
    }
    _plan
      ..clear()
      ..addAll(List.generate(parsed.length, (index) => {
        'step': index + 1,
        'action': parsed[index],
        'status': 'pending',
        'result': null,
      }));
    return getPlan();
  }

  String getNextAction() {
    for (final step in _plan) {
      if (step['status'] == 'pending') {
        step['status'] = 'in_progress';
        return step['action'] as String;
      }
    }
    return 'completed';
  }

  void markStepComplete(int stepNumber, {String? result}) {
    for (final step in _plan) {
      if (step['step'] == stepNumber) {
        step['status'] = 'completed';
        if (result != null) step['result'] = result;
        return;
      }
    }
  }

  void markStepFailed(int stepNumber, String error) {
    for (final step in _plan) {
      if (step['step'] == stepNumber) {
        step['status'] = 'failed';
        step['error'] = error;
        return;
      }
    }
  }

  List<Map<String, dynamic>> getPlan() =>
      _plan.map((step) => Map<String, dynamic>.from(step)).toList(growable: false);

  bool isPlanComplete() =>
      _plan.isNotEmpty && _plan.every((step) => step['status'] == 'completed');

  String getProgress() {
    final completed = _plan.where((step) => step['status'] == 'completed').length;
    final total = _plan.length;
    if (total == 0) return 'لا توجد خطة';
    return 'تقدم: $completed/$total خطوة (${(completed / total * 100).toStringAsFixed(0)}%)';
  }
}
