import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Local notification bridge. Permission is requested only on Android 13+;
/// unsupported platforms fail closed instead of pretending delivery worked.
class NotificationService {
  static const MethodChannel _channel =
      MethodChannel('giant_agent/notifications');

  static Future<bool> init() async {
    try {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        final requested = await Permission.notification.request();
        if (!requested.isGranted) return false;
      }
      return await _channel.invokeMethod<bool>('initialize') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> areNotificationsEnabled() async {
    try {
      final status = await Permission.notification.status;
      if (!status.isGranted) return false;
      return await _channel.invokeMethod<bool>('areNotificationsEnabled') ?? false;
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
      if (!await areNotificationsEnabled()) return false;
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
