import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _notifications.initialize(settings);
    _initialized = true;
  }

  Future<void> cancelAll() async {
    await init();
    await _notifications.cancelAll();
  }

  Future<void> showNotification(String? title, String? body) async {
    await init();
    const android = AndroidNotificationDetails(
      'general_channel',
      'General notifications',
      channelDescription: 'General Giant Agent notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: android);
    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
      title ?? 'Giant Agent',
      body ?? '',
      details,
    );
  }

  Future<void> scheduleNotification(
    DateTime time,
    String title,
    String body,
  ) async {
    await init();
    const android = AndroidNotificationDetails(
      'reminders_channel',
      'Reminders',
      channelDescription: 'Scheduled reminders',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: android);
    await _notifications.zonedSchedule(
      time.millisecondsSinceEpoch.remainder(2147483647),
      title,
      body,
      tz.TZDateTime.from(time, tz.local),
      details,
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static Future<void> showDailyTip() async {
    await init();
    const android = AndroidNotificationDetails(
      'tips_channel',
      'نصائح يومية',
      importance: Importance.low,
    );
    const details = NotificationDetails(android: android);
    await _notifications.show(
      1,
      'نصيحة اليوم',
      'جرب استخدام أوامر جديدة مع الوكيل!',
      details,
    );
  }
}
