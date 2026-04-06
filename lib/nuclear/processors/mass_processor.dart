import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

class MassTextProcessor {
  static const int MAX_TEXTS = 10000;
  List<String> _texts = [];
  List<Map<String, dynamic>> _results = [];
  
  // إضافة نصوص للمعالجة
  void addText(String text) {
    _texts.add(text);
  }
  
  void addMultipleTexts(List<String> texts) {
    _texts.addAll(texts);
  }
  
  // معالجة جميع النصوص
  Future<List<Map<String, dynamic>>> processAll() async {
    _results.clear();
    
    for (int i = 0; i < _texts.length; i++) {
      final result = await _processSingle(_texts[i]);
      _results.add({
        'index': i,
        'text': _texts[i],
        'analysis': result,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
    
    return _results;
  }
  
  // معالجة نص واحد
  Future<Map<String, dynamic>> _processSingle(String text) async {
    final words = text.split(' ');
    final chars = text.length;
    final sentences = text.split(RegExp(r'[.!?]+')).length;
    
    // تحليل المشاعر
    final sentiment = _analyzeSentiment(text);
    
    // استخراج الكلمات المفتاحية
    final keywords = _extractKeywords(text);
    
    // حساب الإحصائيات المتقدمة
    return {
      'length': chars,
      'word_count': words.length,
      'sentence_count': sentences,
      'avg_word_length': chars / words.length,
      'sentiment': sentiment,
      'keywords': keywords,
      'complexity': _calculateComplexity(text),
      'language': _detectLanguage(text),
      'has_numbers': RegExp(r'\d').hasMatch(text),
      'has_arabic': RegExp(r'[\u0600-\u06FF]').hasMatch(text),
    };
  }
  
  String _analyzeSentiment(String text) {
    final positive = ['جيد', 'رائع', 'ممتاز', 'جميل', 'سعيد', 'فرح', 'ممتاز', 'رائع'];
    final negative = ['سيء', 'رديء', 'صعب', 'مؤلم', 'حزين', 'غاضب', 'سوء', 'مشكلة'];
    
    int positiveCount = 0;
    int negativeCount = 0;
    
    for (var word in positive) {
      if (text.contains(word)) positiveCount++;
    }
    for (var word in negative) {
      if (text.contains(word)) negativeCount++;
    }
    
    if (positiveCount > negativeCount) return 'positive';
    if (negativeCount > positiveCount) return 'negative';
    return 'neutral';
  }
  
  List<String> _extractKeywords(String text) {
    final stopWords = ['و', 'في', 'من', 'إلى', 'على', 'عن', 'مع', 'هذا', 'هذه', 'ذلك'];
    final words = text.split(' ');
    final keywords = <String>{};
    
    for (var word in words) {
      if (word.length > 3 && !stopWords.contains(word)) {
        keywords.add(word);
      }
    }
    
    return keywords.toList();
  }
  
  String _calculateComplexity(String text) {
    final words = text.split(' ');
    if (words.length < 50) return 'simple';
    if (words.length < 100) return 'medium';
    return 'complex';
  }
  
  String _detectLanguage(String text) {
    if (RegExp(r'[\u0600-\u06FF]').hasMatch(text)) return 'arabic';
    if (RegExp(r'[a-zA-Z]').hasMatch(text)) return 'english';
    return 'mixed';
  }
  
  // تصدير النتائج
  Future<String> exportResults() async {
    final dir = await getExternalStorageDirectory();
    final file = File('${dir?.path}/mass_processing_results_${DateTime.now().millisecondsSinceEpoch}.json');
    
    final output = {
      'total_processed': _results.length,
      'processing_time': DateTime.now().toIso8601String(),
      'results': _results,
      'statistics': _calculateStatistics(),
    };
    
    await file.writeAsString(json.encode(output));
    return file.path;
  }
  
  Map<String, dynamic> _calculateStatistics() {
    if (_results.isEmpty) return {};
    
    int totalChars = 0;
    int totalWords = 0;
    int positive = 0;
    int negative = 0;
    
    for (var result in _results) {
      totalChars += result['analysis']['length'];
      totalWords += result['analysis']['word_count'];
      if (result['analysis']['sentiment'] == 'positive') positive++;
      if (result['analysis']['sentiment'] == 'negative') negative++;
    }
    
    return {
      'total_chars': totalChars,
      'total_words': totalWords,
      'avg_chars_per_text': totalChars / _results.length,
      'avg_words_per_text': totalWords / _results.length,
      'positive_count': positive,
      'negative_count': negative,
      'neutral_count': _results.length - positive - negative,
    };
  }
  
  void clear() {
    _texts.clear();
    _results.clear();
  }
  
  int get count => _texts.length;
}
