import '../services/llama_service.dart';

class ModelService {
  static final ModelService _instance = ModelService._internal();
  factory ModelService() => _instance;
  ModelService._internal();
  final LlamaService _llama = LlamaService.instance;
  List<Map<String, dynamic>> _models = [];
  String _activeModelId = '';
  bool _isLoading = false;

  Future<void> init() => scanModels();
  Future<void> scanModels() async {
    final found = await _llama.discoverModels();
    _models = found.map((m) => <String, dynamic>{
      'id': m.id, 'name': m.name, 'path': m.path, 'size': m.size,
      'sizeBytes': m.sizeBytes, 'type': 'GGUF', 'isLoaded': false, 'stats': 'available',
    }).toList();
    if (!_models.any((m) => m['id'] == _activeModelId)) _activeModelId = '';
    if (_activeModelId.isEmpty && _models.isNotEmpty) await switchModel(_models.first['id'] as String);
  }
  Future<void> refreshModels() => scanModels();
  Future<bool> importModelFromFile() async {
    final model = await _llama.importModel();
    if (model == null) return false;
    await scanModels();
    return _models.any((m) => m['path'] == model.path);
  }
  Future<bool> switchModel(String modelId) async {
    Map<String, dynamic>? model;
    for (final item in _models) { if (item['id'] == modelId) { model = item; break; } }
    if (model == null || _isLoading) return false;
    _isLoading = true;
    try {
      final ok = await _llama.loadModel(model['path'] as String);
      if (ok) _activeModelId = modelId;
      return ok;
    } finally { _isLoading = false; }
  }
  bool hasActiveModel() => _activeModelId.isNotEmpty && _models.any((m) => m['id'] == _activeModelId);
  String getActiveModelName() => getActiveModel()['name']?.toString() ?? 'لا يوجد';
  String getActiveModelSize() => getActiveModel()['size']?.toString() ?? '0';
  Map<String, dynamic> getActiveModel() {
    for (final m in _models) { if (m['id'] == _activeModelId) return m; }
    return {'id': 'no_model', 'name': 'لا يوجد نموذج GGUF', 'size': '0', 'type': 'NONE'};
  }
  List<Map<String, dynamic>> getModels() => List.unmodifiable(_models);
  Future<String> processInput(String input) async {
    if (!hasActiveModel()) return '⚠️ استورد نموذج GGUF واختره أولاً.';
    try {
      return await _llama.generate(
        'أنت Giant Agent، مساعد محلي يعمل دون اتصال. أجب بلغة المستخدم وبأسلوب واضح ومنظم يشبه تجربة المساعدات الحديثة. ابدأ بالإجابة المباشرة، ثم أضف عند الحاجة قسماً قصيراً بعنوان ملخص الاستدلال يشرح المنهج أو الأسباب الرئيسية بصورة موجزة ومفهومة، ثم خطوات عملية عند الحاجة. لا تعرض التفكير الداخلي التفصيلي أو المداولات الخفية؛ قدّم خلاصة تفسيرية مفيدة فقط. لا تختلق مصادر أو نتائج.\n\nالمستخدم: $input\n\nالمساعد:',
        maxTokens: 512, temperature: .25,
      );
    } catch (e) { return 'تعذر تشغيل النموذج المحلي: $e'; }
  }
}
