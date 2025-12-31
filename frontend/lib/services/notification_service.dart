import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import '../models/task.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  Future<void> init() async {
    tz.initializeTimeZones();
    final String timeZoneName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timeZoneName));
    
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

    // Request Permissions (Android 13+)
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
      await androidImplementation.requestExactAlarmsPermission();
    }
  }

  Future<void> showTestNotification() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'test_channel',
      'Test Notifications',
      channelDescription: 'Channel for testing notifications',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    await flutterLocalNotificationsPlugin.show(
      0,
      'Test Notification',
      'If you see this, notifications are working!',
      platformChannelSpecifics,
    );
  }

  Future<void> scheduleTaskNotification(Task task) async {
    if (task.id == null) return;

    // Parse date and time
    // Date: YYYY-MM-DD, Time: HH:MM
    final DateTime now = DateTime.now();
    final List<String> dateParts = task.date.split('-');
    final List<String> timeParts = task.time.split(':');
    
    final DateTime scheduledDate = DateTime(
      int.parse(dateParts[0]),
      int.parse(dateParts[1]),
      int.parse(dateParts[2]),
      int.parse(timeParts[0]),
      int.parse(timeParts[1]),
    );

    if (scheduledDate.isBefore(now)) {
      // Don't schedule past tasks
      return;
    }

    await flutterLocalNotificationsPlugin.zonedSchedule(
      task.id!,
      task.title,
      task.description,
      tz.TZDateTime.from(scheduledDate, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'remindbuddy_channel',
          'RemindBuddy Notifications',
          channelDescription: 'Channel for task reminders',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: task.repeat == 'daily' 
          ? DateTimeComponents.time 
          : (task.repeat == 'weekly' ? DateTimeComponents.dayOfWeekAndTime : null),
    );
  }
}
