import 'model_service.dart';

/// Compatibility facade over the app's embedded Chaquopy Python runtime.
/// It never launches a host python3 process and never fabricates sample data.
class AdvancedPythonExecutor {
  AdvancedPythonExecutor._internal();
  static final AdvancedPythonExecutor _instance = AdvancedPythonExecutor._internal();
  factory AdvancedPythonExecutor() => _instance;

  final ModelService _models = ModelService();

  Future<Map<String, dynamic>> executeWithFiles(
    String code,
    List<String> inputFiles,
  ) async {
    if (inputFiles.isNotEmpty) {
      return {
        'success': false,
        'output': '',
        'error': 'تم تعطيل تمرير مسارات الملفات المباشرة. استورد الملفات إلى مساحة العمل واستخدم أدوات الملفات الآمنة.',
      };
    }
    try {
      final result = await _models.executePython(code: code);
      return {
        'success': result['ok'] == true,
        'output': result['output']?.toString() ?? '',
        'error': result['error']?.toString() ?? '',
        'duration_ms': result['duration_ms'],
      };
    } catch (error) {
      return {'success': false, 'output': '', 'error': error.toString()};
    }
  }

  Future<String> createDataSciencePipeline(String description) async {
    return 'لم يتم إنشاء بيانات تجريبية أو نتائج وهمية. '
        'أرفق ملف البيانات الفعلي أو ضعه في مساحة العمل، ثم اطلب تحليله. '
        'بعد توفر البيانات يمكن تنفيذ الحسابات المدعومة عبر Python المضمّن. '
        'وصف المهمة: $description';
  }
}
