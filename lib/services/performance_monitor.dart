class PerformanceMonitor {
  static final PerformanceMonitor _instance = PerformanceMonitor._internal();
  factory PerformanceMonitor() => _instance;
  PerformanceMonitor._internal();
  
  final List<PerformanceRecord> _records = [];
  
  void record(String operation, Duration duration, {bool success = true}) {
    _records.add(PerformanceRecord(
      operation: operation,
      duration: duration,
      timestamp: DateTime.now(),
      success: success,
    ));
    
    // الاحتفاظ بآخر 1000 سجل فقط
    if (_records.length > 1000) {
      _records.removeAt(0);
    }
  }
  
  Map<String, dynamic> getStatistics() {
    if (_records.isEmpty) {
      return {'message': 'لا توجد بيانات أداء بعد'};
    }
    
    final operations = <String, List<Duration>>{};
    for (var record in _records) {
      operations.putIfAbsent(record.operation, () => []).add(record.duration);
    }
    
    final stats = <String, dynamic>{};
    for (var entry in operations.entries) {
      final durations = entry.value;
      final avg = durations.fold(Duration.zero, (sum, d) => sum + d) ~/ durations.length;
      stats[entry.key] = {
        'count': durations.length,
        'avg_ms': avg.inMilliseconds,
        'min_ms': durations.reduce((a, b) => a < b ? a : b).inMilliseconds,
        'max_ms': durations.reduce((a, b) => a > b ? a : b).inMilliseconds,
      };
    }
    
    return {
      'total_operations': _records.length,
      'statistics': stats,
      'last_update': DateTime.now(),
    };
  }
  
  String getPerformanceReport() {
    final stats = getStatistics();
    if (stats['total_operations'] == 0) {
      return '📊 لا توجد بيانات أداء متاحة بعد';
    }
    
    var report = '📈 **تقرير أداء النظام**\n\n';
    report += '📊 **إجمالي العمليات:** ${stats['total_operations']}\n\n';
    
    final statsMap = stats['statistics'] as Map<String, dynamic>;
    for (var entry in statsMap.entries) {
      report += '**${entry.key}:**\n';
      report += '  • العدد: ${entry.value['count']}\n';
      report += '  • المتوسط: ${entry.value['avg_ms']}ms\n';
      report += '  • الأسرع: ${entry.value['min_ms']}ms\n';
      report += '  • الأبطأ: ${entry.value['max_ms']}ms\n\n';
    }
    
    return report;
  }
  
  void clear() {
    _records.clear();
  }
}

class PerformanceRecord {
  final String operation;
  final Duration duration;
  final DateTime timestamp;
  final bool success;
  
  PerformanceRecord({
    required this.operation,
    required this.duration,
    required this.timestamp,
    required this.success,
  });
}
