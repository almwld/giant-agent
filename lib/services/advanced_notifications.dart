import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

class AdvancedNotifications {
  static final AdvancedNotifications _instance = AdvancedNotifications._internal();
  factory AdvancedNotifications() => _instance;
  AdvancedNotifications._internal();
  
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  
  Future<void> init() async {
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings();
    const InitializationSettings settings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    
    await _notifications.initialize(settings);
  }
  
  Future<void> showTaskCompleted(String taskName) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'task_channel',
      'Task Notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      DateTime.now().millisecond,
      '✅ مهمة مكتملة',
      'تم إكمال المهمة: $taskName',
      details,
    );
  }
  
  Future<void> showPythonResult(String result) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'python_channel',
      'Python Execution',
      importance: Importance.high,
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      DateTime.now().millisecond,
      '🐍 تنفيذ Python',
      result.length > 100 ? '${result.substring(0, 100)}...' : result,
      details,
    );
  }
  
  Future<void> scheduleReminder(DateTime time, String title, String body) async {
    final tz.TZDateTime scheduled = tz.TZDateTime.from(time, tz.local);
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'reminder_channel',
      'Reminders',
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
}
