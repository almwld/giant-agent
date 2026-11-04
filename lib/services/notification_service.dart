import 'package:flutter/services.dart';

/// Optional platform notification bridge. Unsupported devices fail closed:
/// callers receive false and must not mark an alert as delivered.
class NotificationService {
  static const MethodChannel _channel =
      MethodChannel('giant_agent/notifications');

  static Future<bool> init() async {
    try {
      return await _channel.invokeMethod<bool>('initialize') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> showDailyTip() =>
      NotificationService().showNotification(
        'نصيحة اليوم',
        'جرّب استخدام أدوات الوكيل المحلية لإنجاز مهامك.',
      );

  Future<bool> showNotification(Object? title, Object? body, {int id = 1}) async {
    try {
      return await _channel.invokeMethod<bool>('show', {
            'id': id,
            'title': title?.toString() ?? 'Giant Agent',
            'body': body?.toString() ?? '',
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
