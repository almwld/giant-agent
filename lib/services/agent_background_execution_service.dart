import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps the Android foreground runtime notification aligned with durable
/// agent work. It does not own inference or create another model runtime.
class AgentBackgroundExecutionService {
  AgentBackgroundExecutionService._();

  static final AgentBackgroundExecutionService instance =
      AgentBackgroundExecutionService._();
  static const MethodChannel _channel =
      MethodChannel('giant_agent/background');

  int _activeTasks = 0;
  bool get hasActiveTasks => _activeTasks > 0;

  Future<void> beginTask(String prompt) async {
    _activeTasks++;
    await _invoke('startTask', <String, Object?>{
      'title': 'Giant Agent — تنفيذ مهمة',
      'body': _short(prompt, 150),
    });
  }

  Future<void> updateTask({required String title, String? body}) async {
    if (_activeTasks == 0) return;
    await _invoke('updateTask', <String, Object?>{
      'title': _short(title, 80),
      'body': _short(body ?? 'يواصل الوكيل تنفيذ المهمة وحفظ تقدمها.', 180),
    });
  }

  Future<void> endTask() async {
    if (_activeTasks > 0) _activeTasks--;
    if (_activeTasks == 0) await _invoke('stop');
  }

  Future<void> markRuntimeReady() => _invoke('runtimeReady');

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    try {
      await _channel.invokeMethod<bool>(method, arguments);
    } on MissingPluginException {
      // Non-Android platforms do not provide the native foreground service.
    } on PlatformException catch (error) {
      debugPrint('GiantAgent background service [$method]: ${error.message}');
    } catch (error) {
      debugPrint('GiantAgent background service [$method] failed: $error');
    }
  }

  String _short(String value, int limit) {
    final normalized = value.trim().replaceAll(RegExp(r'\\s+'), ' ');
    if (normalized.length <= limit) return normalized;
    return '${normalized.substring(0, limit)}…';
  }
}
