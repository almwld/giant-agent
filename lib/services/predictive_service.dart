import 'dart:math';

class PredictiveService {
  static final PredictiveService _instance = PredictiveService._internal();
  factory PredictiveService() => _instance;
  PredictiveService._internal();
  
  final Map<String, List<String>> _patterns = {};
  final Map<String, int> _frequency = {};
  
  void learn(String input, String response) {
    final words = input.split(' ');
    for (var word in words) {
      if (word.length > 3) {
        _patterns.putIfAbsent(word, () => []).add(response);
        _frequency[word] = (_frequency[word] ?? 0) + 1;
      }
    }
  }
  
  String predictResponse(String input) {
    final words = input.split(' ');
    String bestMatch = '';
    int maxFrequency = 0;
    
    for (var word in words) {
      if (_frequency.containsKey(word) && _frequency[word]! > maxFrequency) {
        maxFrequency = _frequency[word]!;
        if (_patterns.containsKey(word) && _patterns[word]!.isNotEmpty) {
          bestMatch = _patterns[word]!.last;
        }
      }
    }
    
    return bestMatch;
  }
  
  String getNextActionSuggestion() {
    final suggestions = [
      'تحديث النماذج لتحسين الأداء',
      'مراجعة المحادثات السابقة',
      'تحليل البيانات المخزنة',
      'تجربة أوامر جديدة',
      'مشاركة التطبيق مع الأصدقاء',
    ];
    return suggestions[Random().nextInt(suggestions.length)];
  }
}
