import 'dart:async';
import 'dart:collection';

class PerformanceService {
  static final PerformanceService _instance = PerformanceService._internal();
  factory PerformanceService() => _instance;
  PerformanceService._internal();
  
  // التخزين المؤقت للردود
  final Map<String, String> _responseCache = {};
  final Map<String, DateTime> _cacheTime = {};
  static const int CACHE_DURATION = 300000; // 5 دقائق
  
  // قائمة انتظار للمعالجة
  final Queue<Future Function()> _taskQueue = Queue();
  bool _isProcessing = false;
  
  // إحصائيات الأداء
  int _totalRequests = 0;
  int _cachedResponses = 0;
  double _averageResponseTime = 0;
  
  // الحصول على رد من التخزين المؤقت
  String? getCachedResponse(String input) {
    if (_responseCache.containsKey(input) && _cacheTime.containsKey(input)) {
      final age = DateTime.now().difference(_cacheTime[input]!).inMilliseconds;
      if (age < CACHE_DURATION) {
        _cachedResponses++;
        return _responseCache[input];
      }
    }
    return null;
  }
  
  // حفظ رد في التخزين المؤقت
  void cacheResponse(String input, String response) {
    _responseCache[input] = response;
    _cacheTime[input] = DateTime.now();
    
    // تنظيف الذاكرة المؤقتة إذا كبرت
    if (_responseCache.length > 1000) {
      _cleanCache();
    }
  }
  
  void _cleanCache() {
    final keysToRemove = <String>[];
    final now = DateTime.now();
    
    for (var entry in _cacheTime.entries) {
      if (now.difference(entry.value).inMilliseconds > CACHE_DURATION) {
        keysToRemove.add(entry.key);
      }
    }
    
    for (var key in keysToRemove) {
      _responseCache.remove(key);
      _cacheTime.remove(key);
    }
  }
  
  // معالجة متسلسلة للمهام
  Future<T> queueTask<T>(Future<T> Function() task) async {
    final completer = Completer<T>();
    
    _taskQueue.add(() async {
      try {
        final result = await task();
        completer.complete(result);
      } catch (e) {
        completer.completeError(e);
      }
    });
    
    if (!_isProcessing) {
      _processQueue();
    }
    
    return completer.future;
  }
  
  Future<void> _processQueue() async {
    if (_isProcessing || _taskQueue.isEmpty) return;
    
    _isProcessing = true;
    
    while (_taskQueue.isNotEmpty) {
      final task = _taskQueue.removeFirst();
      await task();
      await Future.delayed(const Duration(milliseconds: 10)); // راحة بين المهام
    }
    
    _isProcessing = false;
  }
  
  // تسجيل وقت الاستجابة
  void recordResponseTime(int milliseconds) {
    _totalRequests++;
    _averageResponseTime = (_averageResponseTime * (_totalRequests - 1) + milliseconds) / _totalRequests;
  }
  
  // الحصول على إحصائيات الأداء
  Map<String, dynamic> getPerformanceStats() {
    return {
      'total_requests': _totalRequests,
      'cached_responses': _cachedResponses,
      'cache_hit_rate': _totalRequests > 0 ? (_cachedResponses / _totalRequests * 100).toStringAsFixed(1) : '0',
      'average_response_time_ms': _averageResponseTime.toStringAsFixed(0),
      'queue_size': _taskQueue.length,
    };
  }
  
  void clearCache() {
    _responseCache.clear();
    _cacheTime.clear();
    _cachedResponses = 0;
  }
}
