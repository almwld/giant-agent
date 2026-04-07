import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();
  
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;
  
  Future<void> init() async {
    if (_isInitialized) return;
    
    tz.initializeTimeZones();
    
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings();
    const InitializationSettings settings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    
    await _notifications.initialize(settings);
    _isInitialized = true;
  }
  
  Future<void> showNotification(String title, String body, {int? id}) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'chat_channel',
      'Chat Notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails);
    
    await _notifications.show(id ?? DateTime.now().millisecond, title, body, details);
  }
  
  Future<void> scheduleNotification(DateTime time, String title, String body) async {
    final tz.TZDateTime scheduled = tz.TZDateTime.from(time, tz.local);
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'scheduled_channel',
      'Scheduled Notifications',
      importance: Importance.high,
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails);
    
    await _notifications.zonedSchedule(
      time.millisecondsSinceEpoch,
      title,
      body,
      scheduled,
      details,
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
  
  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }
}
