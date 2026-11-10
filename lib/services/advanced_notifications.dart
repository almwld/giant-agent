import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class AdvancedNotifications {
  static final AdvancedNotifications _instance = AdvancedNotifications._internal();
  factory AdvancedNotifications() => _instance;
  AdvancedNotifications._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);
    await _notifications.initialize(settings);
    _initialized = true;
  }

  Future<void> showTaskCompleted(String taskName) async {
    await init();
    const android = AndroidNotificationDetails('task_channel', 'Task Notifications',
        importance: Importance.high, priority: Priority.high);
    await _notifications.show(DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
        'مهمة مكتملة', 'تم إكمال المهمة: $taskName',
        const NotificationDetails(android: android));
  }

  Future<void> showPythonResult(String result) async {
    await init();
    const android = AndroidNotificationDetails('python_channel', 'Python Execution',
        importance: Importance.high);
    final body = result.length > 100 ? '${result.substring(0, 100)}...' : result;
    await _notifications.show(DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
        'تنفيذ Python', body, const NotificationDetails(android: android));
  }

  Future<void> scheduleReminder(DateTime time, String title, String body) async {
    await init();
    const android = AndroidNotificationDetails('reminder_channel', 'Reminders',
        importance: Importance.high);
    await _notifications.zonedSchedule(
      time.millisecondsSinceEpoch.remainder(2147483647),
      title, body, tz.TZDateTime.from(time, tz.local),
      const NotificationDetails(android: android),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}
