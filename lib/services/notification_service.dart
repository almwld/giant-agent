import 'package:flutter/services.dart';

/// Thin bridge to Android's native notification manager; no fake delivery
/// state is reported when the operating system denies notification access.
class NotificationService {
  static const MethodChannel _channel =
      MethodChannel('giant_agent/notifications');

  static Future<bool> init() async {
    return await _channel.invokeMethod<bool>('initialize') ?? false;
  }

  static Future<bool> showDailyTip() async {
    return NotificationService().showNotification(
      'نصيحة اليوم',
      'جرّب استخدام أدوات الوكيل المحلية لإنجاز مهامك.',
    );
  }

  Future<bool> showNotification(Object? title, Object? body, {int id = 1}) async {
    return await _channel.invokeMethod<bool>('show', {
          'id': id,
          'title': title?.toString() ?? 'Giant Agent',
          'body': body?.toString() ?? '',
        }) ??
        false;
  }
}
