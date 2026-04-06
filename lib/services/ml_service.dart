import 'dart:math';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

class MLService {
  static final MLService _instance = MLService._internal();
  factory MLService() => _instance;
  MLService._internal();
  
  Database? _db;
  Map<String, double> _wordWeights = {};
  Map<String, List<String>> _patterns = {};
  
  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      '${dir.path}/ml_model.db',
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE patterns (
            id INTEGER PRIMARY KEY,
            input TEXT,
            intent TEXT,
            frequency INTEGER,
            last_used INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE weights (
            word TEXT PRIMARY KEY,
            weight REAL
          )
        ''');
      },
    );
    await _loadWeights();
  }
  
  Future<void> _loadWeights() async {
    final results = await _db?.query('weights');
    if (results != null) {
      for (var row in results) {
        _wordWeights[row['word']] = row['weight'];
      }
    }
  }
  
  Future<String> predictIntent(String input) async {
    final words = input.split(' ');
    Map<String, double> scores = {
      'greeting': 0,
      'question': 0,
      'command': 0,
      'calculation': 0,
      'code': 0,
      'website': 0,
      'analysis': 0,
      'reminder': 0,
    };
    
    for (var word in words) {
      if (_wordWeights.containsKey(word)) {
        final weight = _wordWeights[word]!;
        if (word.contains('مرحبا') || word.contains('السلام')) scores['greeting'] = scores['greeting']! + weight;
        if (word.contains('ما') || word.contains('كيف')) scores['question'] = scores['question']! + weight;
        if (word.contains('أنشئ') || word.contains('اعمل')) scores['command'] = scores['command']! + weight;
        if (word.contains('+') || word.contains('-')) scores['calculation'] = scores['calculation']! + weight;
        if (word.contains('كود') || word.contains('برنامج')) scores['code'] = scores['code']! + weight;
        if (word.contains('موقع') || word.contains('صفحة')) scores['website'] = scores['website']! + weight;
        if (word.contains('حلل') || word.contains('اقترح')) scores['analysis'] = scores['analysis']! + weight;
        if (word.contains('ذكرني') || word.contains('تذكير')) scores['reminder'] = scores['reminder']! + weight;
      }
    }
    
    String bestIntent = 'chat';
    double bestScore = 0;
    scores.forEach((intent, score) {
      if (score > bestScore) {
        bestScore = score;
        bestIntent = intent;
      }
    });
    
    return bestIntent;
  }
  
  Future<void> learn(String input, String intent, bool wasCorrect) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // تحديث التردد
    final existing = await _db?.query('patterns', where: 'input = ?', whereArgs: [input]);
    if (existing != null && existing.isNotEmpty) {
      await _db?.update('patterns', {
        'frequency': (existing.first['frequency'] as int) + 1,
        'last_used': now,
      }, where: 'id = ?', whereArgs: [existing.first['id']]);
    } else {
      await _db?.insert('patterns', {
        'input': input,
        'intent': intent,
        'frequency': 1,
        'last_used': now,
      });
    }
    
    // تحديث الأوزان
    final words = input.split(' ');
    for (var word in words) {
      double newWeight = _wordWeights[word] ?? 0.5;
      if (wasCorrect) {
        newWeight = min(1.0, newWeight + 0.05);
      } else {
        newWeight = max(0.0, newWeight - 0.03);
      }
      _wordWeights[word] = newWeight;
      
      await _db?.insert('weights', {
        'word': word,
        'weight': newWeight,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }
  
  Future<List<Map<String, dynamic>>> getSuggestions(String input) async {
    final words = input.split(' ');
    final suggestions = <Map<String, dynamic>>[];
    
    for (var word in words) {
      final results = await _db?.query('patterns', where: 'input LIKE ?', whereArgs: ['%$word%'], limit: 5);
      if (results != null) {
        for (var result in results) {
          suggestions.add({
            'input': result['input'],
            'intent': result['intent'],
            'frequency': result['frequency'],
          });
        }
      }
    }
    
    suggestions.sort((a, b) => (b['frequency'] as int).compareTo(a['frequency'] as int));
    return suggestions.take(5).toList();
  }
  
  void dispose() {
    _db?.close();
  }
}
