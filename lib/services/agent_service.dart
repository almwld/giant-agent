import 'package:path_provider/path_provider.dart';
import '../core/ai/super_brain.dart';

class AgentService {
  final SuperBrain _brain = SuperBrain();
  
  Future<void> init() async {
    await _brain.initialize();
  }
  
  Future<String> process(String input) async {
    // تحليل النية باستخدام العقل الفائق
    final intentAnalysis = await _brain.analyzeIntent(input);
    final intent = intentAnalysis['intent'];
    final confidence = intentAnalysis['confidence'];
    
    // توليد الاستجابة الفائقة
    final response = await _brain.generateSuperResponse(input, intent, confidence);
    
    // التعلم من التجربة
    await _brain.learnFromExperience(input, response, true, 500);
    
    return response;
  }
  
  Future<Map<String, dynamic>> getStats() async {
    return await _brain.getPerformanceStats();
  }
  
  void dispose() {
    _brain.dispose();
  }
}
