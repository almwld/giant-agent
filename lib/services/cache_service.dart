class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();
  
  final Map<String, CacheEntry> _cache = {};
  final int _maxCacheSize = 100;
  final Duration _defaultTTL = const Duration(minutes: 30);
  
  void set(String key, dynamic value, {Duration? ttl}) {
    if (_cache.length >= _maxCacheSize) {
      _removeOldest();
    }
    
    _cache[key] = CacheEntry(
      value: value,
      expiry: DateTime.now().add(ttl ?? _defaultTTL),
    );
  }
  
  dynamic get(String key) {
    final entry = _cache[key];
    if (entry != null && !entry.isExpired) {
      return entry.value;
    }
    _cache.remove(key);
    return null;
  }
  
  bool has(String key) {
    final entry = _cache[key];
    if (entry != null && !entry.isExpired) {
      return true;
    }
    _cache.remove(key);
    return false;
  }
  
  void clear() {
    _cache.clear();
  }
  
  void _removeOldest() {
    if (_cache.isNotEmpty) {
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey);
    }
  }
  
  int get size => _cache.length;
}

class CacheEntry {
  final dynamic value;
  final DateTime expiry;
  
  CacheEntry({required this.value, required this.expiry});
  
  bool get isExpired => DateTime.now().isAfter(expiry);
}
