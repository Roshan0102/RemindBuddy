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

  static String debugTimeZone = 'Unknown';
  static String debugError = 'None';
  static bool isInitialized = false;

  NotificationService._internal();

  Future<void> init() async {
    tz.initializeTimeZones();
    
    try {
      final String timeZoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
      debugTimeZone = timeZoneName;
      isInitialized = true;
    } catch (e) {
      print('Error getting local timezone: $e');
      debugError = e.toString();
      // Fallback to UTC if timezone detection fails
      tz.setLocalLocation(tz.getLocation('UTC'));
      debugTimeZone = 'UTC (Fallback)';
    }
    
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
    final String timeZoneName = tz.local.name;
    final DateTime now = DateTime.now();
    final tz.TZDateTime tzNow = tz.TZDateTime.now(tz.local);
    
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
      'Test Notification ($timeZoneName)',
      'System: ${now.hour}:${now.minute} | TZ: ${tzNow.hour}:${tzNow.minute}',
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
    
    // Construct the scheduled date in the Local Timezone
    // We use DateTime first to parse the components safely
    final DateTime localScheduledDate = DateTime(
      int.parse(dateParts[0]),
      int.parse(dateParts[1]),
      int.parse(dateParts[2]),
      int.parse(timeParts[0]),
      int.parse(timeParts[1]),
    );

    // Convert to TZDateTime
    // If tz.local is correctly set to 'Asia/Kolkata', this will map 1:05 PM Local -> 1:05 PM Asia/Kolkata
    final tz.TZDateTime scheduledDate = tz.TZDateTime.from(localScheduledDate, tz.local);

    if (scheduledDate.isBefore(tz.TZDateTime.now(tz.local).subtract(const Duration(minutes: 1)))) {
      // Don't schedule tasks that are more than 1 minute in the past
      print('Task ${task.id} is in the past: $scheduledDate');
      return;
    }
    
    // If the task is in the past but within 1 minute (e.g. processing delay), schedule it for 5 seconds from now
    tz.TZDateTime finalScheduledDate = scheduledDate;
    if (scheduledDate.isBefore(tz.TZDateTime.now(tz.local))) {
       finalScheduledDate = tz.TZDateTime.now(tz.local).add(const Duration(seconds: 5));
    }

    await flutterLocalNotificationsPlugin.zonedSchedule(
      task.id!,
      task.title,
      task.description,
      finalScheduledDate,
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
