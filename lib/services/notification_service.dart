import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  
  static Future<void> init() async {
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings settings = InitializationSettings(android: androidSettings);
    await _notifications.initialize(settings);
  }
  
  static Future<void> showDailyTip() async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'tips_channel', 'نصائح يومية',
      importance: Importance.low,
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails);
    await _notifications.show(1, 'نصيحة اليوم', 'جرب استخدام أوامر جديدة مع الوكيل!', details);
  }
}
