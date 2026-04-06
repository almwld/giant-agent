import 'dart:convert';
import 'dart:math';
import 'package:path_provider/path_provider.dart';

class NuclearAnalyzer {
  
  // تحليل 1000 نص دفعة واحدة
  static Future<Map<String, dynamic>> analyzeMassTexts(List<String> texts) async {
    final startTime = DateTime.now();
    final results = <Map<String, dynamic>>[];
    
    for (int i = 0; i < texts.length; i++) {
      final analysis = await _deepAnalyze(texts[i]);
      results.add({
        'index': i,
        'text_preview': texts[i].length > 100 ? '${texts[i].substring(0, 100)}...' : texts[i],
        'analysis': analysis,
      });
    }
    
    final endTime = DateTime.now();
    final duration = endTime.difference(startTime).inMilliseconds;
    
    // إحصائيات شاملة
    final statistics = _calculateMassStatistics(results);
    
    return {
      'total_analyzed': results.length,
      'processing_time_ms': duration,
      'average_time_per_text': duration / results.length,
      'statistics': statistics,
      'results': results,
    };
  }
  
  static Future<Map<String, dynamic>> _deepAnalyze(String text) async {
    final words = text.split(' ');
    final sentences = text.split(RegExp(r'[.!?]+'));
    
    // تحليل متقدم
    return {
      'length': text.length,
      'word_count': words.length,
      'sentence_count': sentences.length,
      'avg_word_length': text.length / words.length,
      'unique_words': Set.from(words).length,
      'char_frequency': _getCharFrequency(text),
      'word_frequency': _getWordFrequency(words),
      'sentiment_score': _calculateSentimentScore(text),
      'readability_score': _calculateReadability(text),
      'language_detection': _detectLanguages(text),
      'entities': _extractEntities(text),
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
  
  static Map<String, int> _getCharFrequency(String text) {
    final freq = <String, int>{};
    for (var char in text.runes) {
      final charStr = String.fromCharCode(char);
      freq[charStr] = (freq[charStr] ?? 0) + 1;
    }
    return freq;
  }
  
  static Map<String, int> _getWordFrequency(List<String> words) {
    final freq = <String, int>{};
    for (var word in words) {
      final lower = word.toLowerCase();
      freq[lower] = (freq[lower] ?? 0) + 1;
    }
    return freq;
  }
  
  static double _calculateSentimentScore(String text) {
    final positive = ['good', 'great', 'excellent', 'amazing', 'wonderful', 'perfect', 'beautiful'];
    final negative = ['bad', 'terrible', 'awful', 'horrible', 'worst', 'poor', 'ugly'];
    
    final lower = text.toLowerCase();
    int pos = 0, neg = 0;
    
    for (var word in positive) {
      if (lower.contains(word)) pos++;
    }
    for (var word in negative) {
      if (lower.contains(word)) neg++;
    }
    
    final total = pos + neg;
    if (total == 0) return 0.5;
    return pos / total;
  }
  
  static double _calculateReadability(String text) {
    final words = text.split(' ');
    final sentences = text.split(RegExp(r'[.!?]+'));
    
    if (sentences.isEmpty || words.isEmpty) return 0;
    
    final avgWordsPerSentence = words.length / sentences.length;
    final avgCharsPerWord = text.length / words.length;
    
    // صيغة مبسطة لقياس القراءة
    return 206.835 - (1.015 * avgWordsPerSentence) - (84.6 * avgCharsPerWord / 100);
  }
  
  static List<String> _detectLanguages(String text) {
    final languages = <String>[];
    if (RegExp(r'[\u0600-\u06FF]').hasMatch(text)) languages.add('arabic');
    if (RegExp(r'[a-zA-Z]').hasMatch(text)) languages.add('english');
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(text)) languages.add('chinese');
    if (RegExp(r'[а-яА-Я]').hasMatch(text)) languages.add('russian');
    return languages;
  }
  
  static List<String> _extractEntities(String text) {
    final entities = <String>[];
    final patterns = {
      'email': r'\b[\w\.-]+@[\w\.-]+\.\w+\b',
      'url': r'https?://[^\s]+',
      'number': r'\b\d+(?:\.\d+)?\b',
      'hashtag': r'#\w+',
      'mention': r'@\w+',
    };
    
    for (var entry in patterns.entries) {
      final matches = RegExp(entry.value).allMatches(text);
      for (var match in matches) {
        entities.add('${entry.key}:${match.group(0)}');
      }
    }
    
    return entities;
  }
  
  static Map<String, dynamic> _calculateMassStatistics(List<Map<String, dynamic>> results) {
    int totalChars = 0;
    int totalWords = 0;
    double totalSentiment = 0;
    
    for (var result in results) {
      totalChars += result['analysis']['length'];
      totalWords += result['analysis']['word_count'];
      totalSentiment += result['analysis']['sentiment_score'];
    }
    
    final n = results.length;
    return {
      'total_chars': totalChars,
      'total_words': totalWords,
      'avg_chars_per_text': totalChars / n,
      'avg_words_per_text': totalWords / n,
      'avg_sentiment': totalSentiment / n,
      'avg_readability': results.map((r) => r['analysis']['readability_score']).reduce((a, b) => a + b) / n,
    };
  }
  
  // تصدير النتائج إلى JSON
  static Future<String> exportToJson(Map<String, dynamic> analysis) async {
    final dir = await getExternalStorageDirectory();
    final file = File('${dir?.path}/nuclear_analysis_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(json.encode(analysis));
    return file.path;
  }
  
  // توليد تقرير HTML
  static Future<String> exportToHtml(Map<String, dynamic> analysis) async {
    final dir = await getExternalStorageDirectory();
    final file = File('${dir?.path}/nuclear_report_${DateTime.now().millisecondsSinceEpoch}.html');
    
    final html = '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Nuclear Analysis Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%); }
        .container { max-width: 1200px; margin: auto; background: white; padding: 20px; border-radius: 10px; }
        h1 { color: #2a5298; }
        .stat-card { display: inline-block; margin: 10px; padding: 20px; background: #f0f0f0; border-radius: 10px; min-width: 150px; text-align: center; }
        .stat-value { font-size: 24px; font-weight: bold; color: #2a5298; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #2a5298; color: white; }
        tr:nth-child(even) { background-color: #f9f9f9; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🧠 NUCLEAR ANALYSIS REPORT</h1>
        <p>Generated by Nuclear Giant Agent | ${DateTime.now()}</p>
        <hr>
        
        <div>
            <div class="stat-card">
                <div class="stat-value">${analysis['total_analyzed']}</div>
                <div>Texts Analyzed</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">${analysis['processing_time_ms']}ms</div>
                <div>Processing Time</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">${(analysis['average_time_per_text']).toStringAsFixed(2)}ms</div>
                <div>Avg per Text</div>
            </div>
        </div>
        
        <h2>📊 Statistics</h2>
        <table>
            <tr><th>Metric</th><th>Value</th></tr>
            <tr><td>Total Characters</td><td>${analysis['statistics']['total_chars']}</td></tr>
            <tr><td>Total Words</td><td>${analysis['statistics']['total_words']}</td></tr>
            <tr><td>Avg Characters/Text</td><td>${analysis['statistics']['avg_chars_per_text'].toStringAsFixed(2)}</td></tr>
            <tr><td>Avg Words/Text</td><td>${analysis['statistics']['avg_words_per_text'].toStringAsFixed(2)}</td></tr>
            <tr><td>Avg Sentiment</td><td>${analysis['statistics']['avg_sentiment'].toStringAsFixed(3)}</td></tr>
        </table>
        
        <p style="margin-top: 20px; text-align: center; color: #666;">
            🚀 Nuclear Giant Agent - Destroying All Competitors
        </p>
    </div>
</body>
</html>
''';
    
    await file.writeAsString(html);
    return file.path;
  }
}
