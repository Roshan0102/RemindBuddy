import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import '../models/task.dart';
import 'log_service.dart';

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
      String timeZoneName = await FlutterTimezone.getLocalTimezone();
      
      // FIX: Handle deprecated timezone names
      if (timeZoneName == 'Asia/Calcutta') {
        timeZoneName = 'Asia/Kolkata';
      }
      
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
      
      // Create the channel immediately so it shows in settings
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'remindbuddy_channel', // id
        'RemindBuddy Notifications', // title
        description: 'Channel for task reminders', // description
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );
      await androidImplementation.createNotificationChannel(channel);
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
    final DateTime now = DateTime.now();
    final List<String> dateParts = task.date.split('-');
    final List<String> timeParts = task.time.split(':');
    
    // Construct the scheduled date in the Local Timezone
    final DateTime localScheduledDate = DateTime(
      int.parse(dateParts[0]),
      int.parse(dateParts[1]),
      int.parse(dateParts[2]),
      int.parse(timeParts[0]),
      int.parse(timeParts[1]),
    );

    // Convert to TZDateTime
    final tz.TZDateTime scheduledDate = tz.TZDateTime.from(localScheduledDate, tz.local);
    
    LogService().log('Scheduling Task ${task.id}: "${task.title}"');
    LogService().log('  - Input: ${task.date} ${task.time}');
    LogService().log('  - Local Date: $localScheduledDate');
    LogService().log('  - TZ Date: $scheduledDate (${scheduledDate.location})');
    LogService().log('  - Current TZ Time: ${tz.TZDateTime.now(tz.local)}');

    if (scheduledDate.isBefore(tz.TZDateTime.now(tz.local).subtract(const Duration(minutes: 1)))) {
      LogService().error('  - Task is in the past! Skipping.');
      return;
    }
    
    // Grace period handling
    tz.TZDateTime finalScheduledDate = scheduledDate;
    if (scheduledDate.isBefore(tz.TZDateTime.now(tz.local))) {
       LogService().log('  - Task is slightly past, pushing +5s');
       finalScheduledDate = tz.TZDateTime.now(tz.local).add(const Duration(seconds: 5));
    }

    try {
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
            playSound: true,
            enableVibration: true,
            fullScreenIntent: true, // This helps bypass DND on some devices
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: task.repeat == 'daily' 
            ? DateTimeComponents.time 
            : (task.repeat == 'weekly' ? DateTimeComponents.dayOfWeekAndTime : null),
      );
      LogService().log('  - SUCCESS: Scheduled for $finalScheduledDate');
    } catch (e) {
      LogService().error('  - FAILED to schedule', e);
    }
  }
  Future<void> cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
    LogService().log('Cancelled notification for Task $id');
  }
}
