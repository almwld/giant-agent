import '../../agent/architecture/subagent_orchestrator.dart';
import 'agent_kernel_store.dart';

typedef RecoveredSubagentExecutor = Future<String> Function({
  required KernelRequestRecord parent,
  required Map<String, dynamic> task,
  required Map<String, String> dependencyResults,
});

/// Durable child-level recovery coordinator.
/// A resume is never automatic: callers must supply an explicit side-effect
/// disposition, and SQLite atomically claims the child before execution.
class SubagentRecoveryCoordinator {
  const SubagentRecoveryCoordinator(this._store);

  final AgentKernelStore _store;

  Future<List<Map<String, dynamic>>> childrenForRequest(String requestId) =>
      _store.subagentsForRequest(requestId);

  Future<Map<String, dynamic>?> child(String taskId) =>
      _store.getSubagent(taskId);

  Future<String> resume({
    required String taskId,
    required String sideEffectDisposition,
    required RecoveredSubagentExecutor execute,
  }) async {
    final before = await _store.getSubagent(taskId);
    if (before == null) throw StateError('الوكيل الفرعي غير موجود.');
    final parentId = before['parent_request_id']?.toString() ?? '';
    final parent = await _store.getRequest(parentId);
    if (parent == null) throw StateError('تعذر استعادة الطلب الأصلي للوكيل.');

    final claimed = await _store.claimSubagentResume(taskId,
      sideEffectDisposition: sideEffectDisposition);
    final rawDependencies = claimed['dependency_results_snapshot'];
    final dependencies = <String, String>{};
    if (rawDependencies is Map) {
      for (final entry in rawDependencies.entries) {
        dependencies[entry.key.toString()] = entry.value.toString();
      }
    }

    try {
      final result = await execute(
        parent: parent,
        task: claimed,
        dependencyResults: Map.unmodifiable(dependencies),
      );
      if (result.trim().isEmpty) throw StateError('عاد الوكيل بنتيجة فارغة.');
      await _store.finishSubagentResume(taskId,
        status: 'completed', result: result);
      return result;
    } on SubagentInterrupted catch (error) {
      await _store.finishSubagentResume(taskId,
        status: 'interrupted', error: error.toString());
      rethrow;
    } catch (error) {
      await _store.finishSubagentResume(taskId,
        status: 'failed', error: error.toString());
      rethrow;
    }
  }
}
