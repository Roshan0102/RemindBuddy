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

  // Background Handler
  @pragma('vm:entry-point')
  static void notificationTapBackground(NotificationResponse notificationResponse) {
    print('Notification action tapped: ${notificationResponse.actionId}');
    if (notificationResponse.actionId == 'NO_ACTION') {
      // Schedule for 3 hours later
      _scheduleSnooze(notificationResponse.id!, notificationResponse.payload);
    }
    // YES_ACTION does nothing, effectively cancelling the nag loop for today
  }

  static Future<void> _scheduleSnooze(int id, String? payload) async {
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    tz.initializeTimeZones();
    final String timeZoneName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timeZoneName));

    var now = tz.TZDateTime.now(tz.local);
    var nextReminder = now.add(const Duration(hours: 3));

    // Quiet Hours Logic: 11 PM (23:00) to 6 AM (06:00)
    if (nextReminder.hour >= 23 || nextReminder.hour < 6) {
      // If it falls in quiet hours, push to 6 AM next day
      if (nextReminder.hour >= 23) {
         nextReminder = tz.TZDateTime(tz.local, now.year, now.month, now.day + 1, 6, 0);
      } else {
         nextReminder = tz.TZDateTime(tz.local, now.year, now.month, now.day, 6, 0);
      }
    }

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id + 999, // Use a temporary ID for snooze
      'Reminder: ${payload ?? "Task"}',
      'You snoozed this task. Do it now!',
      nextReminder,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'remindbuddy_channel',
          'RemindBuddy Notifications',
          channelDescription: 'Channel for task reminders',
          importance: Importance.max,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(
            'You snoozed this task. Do it now!',
            contentTitle: 'Reminder: ${payload ?? "Task"}',
            summaryText: 'Nag Mode Active',
          ),
          actions: [
            AndroidNotificationAction(
              'YES_ACTION', 
              'YES (Done)', 
              showsUserInterface: false,
              cancelNotification: true,
            ),
            AndroidNotificationAction(
              'NO_ACTION', 
              'NO (Remind in 3h)', 
              showsUserInterface: false,
              cancelNotification: true,
            ),
          ],
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

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

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: notificationTapBackground,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

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
    
    final tzNow = tz.TZDateTime.now(tz.local);
    final difference = scheduledDate.difference(tzNow);
    LogService().log('  - Current TZ Time: $tzNow');
    LogService().log('  - Difference: ${difference.inSeconds} seconds');

    if (scheduledDate.isBefore(tzNow.subtract(const Duration(minutes: 1)))) {
      LogService().log('  - Task is in the past. Not scheduling notification.');
      return;
    }
    
    // Grace period handling
    tz.TZDateTime finalScheduledDate = scheduledDate;
    if (scheduledDate.isBefore(tzNow)) {
       LogService().log('  - Task is slightly past, pushing +5s');
       finalScheduledDate = tzNow.add(const Duration(seconds: 5));
    }

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        task.id!,
        task.title,
        task.description,
        finalScheduledDate,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'remindbuddy_channel',
            'RemindBuddy Notifications',
            styleInformation: BigTextStyleInformation(
              task.description,
              contentTitle: task.title,
              summaryText: task.isAnnoying ? 'Nag Mode Active' : null,
            ),
            actions: task.isAnnoying ? [
              AndroidNotificationAction(
                'YES_ACTION', 
                'YES (Done)', 
                showsUserInterface: false,
                cancelNotification: true,
              ),
              AndroidNotificationAction(
                'NO_ACTION', 
                'NO (Remind in 3h)', 
                showsUserInterface: false,
                cancelNotification: true,
              ),
            ] : null,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: task.repeat == 'daily' 
            ? DateTimeComponents.time 
            : (task.repeat == 'weekly' ? DateTimeComponents.dayOfWeekAndTime : null),
      );
      LogService().log('  - SUCCESS: Scheduled for $finalScheduledDate (Annoying: ${task.isAnnoying})');

      // Handle Custom Repeat (e.g., custom:10)
      if (task.repeat.startsWith('custom:')) {
        final int days = int.tryParse(task.repeat.split(':')[1]) ?? 0;
        if (days > 0) {
          // Schedule next 5 occurrences
          for (int i = 1; i <= 5; i++) {
            final nextDate = finalScheduledDate.add(Duration(days: days * i));
            await flutterLocalNotificationsPlugin.zonedSchedule(
              task.id! + (i * 100000), // Unique ID for future instances
              task.title,
              task.description,
              nextDate,
              NotificationDetails(
                android: AndroidNotificationDetails(
                  'remindbuddy_channel',
                  'RemindBuddy Notifications',
                  styleInformation: BigTextStyleInformation(
                    task.description,
                    contentTitle: task.title,
                    summaryText: task.isAnnoying ? 'Nag Mode Active' : null,
                  ),
                  actions: task.isAnnoying ? [
                    AndroidNotificationAction(
                      'YES_ACTION', 
                      'YES (Done)', 
                      showsUserInterface: false,
                      cancelNotification: true,
                    ),
                    AndroidNotificationAction(
                      'NO_ACTION', 
                      'NO (Remind in 3h)', 
                      showsUserInterface: false,
                      cancelNotification: true,
                    ),
                  ] : null,
                ),
              ),
              androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
              uiLocalNotificationDateInterpretation:
                  UILocalNotificationDateInterpretation.absoluteTime,
            );
            LogService().log('  - Scheduled future instance for $nextDate');
          }
        }
      }
    } catch (e) {
      LogService().error('  - FAILED to schedule', e);
    }
  }
  Future<void> showImmediateNotification() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'remindbuddy_channel',
      'RemindBuddy Notifications',
      channelDescription: 'Channel for task reminders',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true,
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      999, // Special ID for test
      'Immediate Test',
      'If you see this, Notifications are working!',
      platformChannelSpecifics,
    );
    LogService().log('Triggered Immediate Notification');
  }

  Future<void> checkPermissions() async {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      final bool? areNotificationsEnabled = 
          await androidImplementation.areNotificationsEnabled();
      LogService().log('NOTIFICATIONS ENABLED: $areNotificationsEnabled');
      
      // Note: exact alarm check isn't directly exposed in older versions of the plugin
      // but we can try to request it again to see if it prompts or logs
      await androidImplementation.requestExactAlarmsPermission();
      LogService().log('Requested Exact Alarm Permission check');
    }
  }

  Future<void> checkPendingNotifications() async {
    final List<PendingNotificationRequest> pendingNotificationRequests =
        await flutterLocalNotificationsPlugin.pendingNotificationRequests();
    
    LogService().log('--- PENDING NOTIFICATIONS ---');
    if (pendingNotificationRequests.isEmpty) {
      LogService().log('No pending notifications found.');
    } else {
      for (var notification in pendingNotificationRequests) {
        LogService().log(
            'ID: ${notification.id}, Title: ${notification.title}, Body: ${notification.body}, Payload: ${notification.payload}');
      }
    }
    LogService().log('-----------------------------');
  }

  // Schedule Daily Reminder (repeats every day at the same time)
  Future<void> scheduleDailyReminder(dynamic reminder) async {
    // Support both DailyReminder and Task objects
    final int id = (reminder.id ?? 0) + 100000; // Offset to avoid conflicts with tasks
    final String title = reminder.title;
    final String description = reminder.description;
    final String timeStr = reminder.time;
    final bool isAnnoying = reminder.isAnnoying ?? false;

    // Parse time
    final List<String> timeParts = timeStr.split(':');
    final int hour = int.parse(timeParts[0]);
    final int minute = int.parse(timeParts[1]);

    // Create the first occurrence for today (or tomorrow if time has passed)
    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    // If the time has already passed today, schedule for tomorrow
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    LogService().log('Scheduling Daily Reminder $id: "$title"');
    LogService().log('  - Time: $timeStr');
    LogService().log('  - First occurrence: $scheduledDate');
    LogService().log('  - Annoying: $isAnnoying');

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        description,
        scheduledDate,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'remindbuddy_channel',
            'RemindBuddy Notifications',
            channelDescription: 'Channel for daily reminders',
            importance: Importance.max,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(
              description,
              contentTitle: title,
              summaryText: isAnnoying ? 'Daily Nag Mode Active' : 'Daily Reminder',
            ),
            actions: isAnnoying ? [
              AndroidNotificationAction(
                'YES_ACTION',
                'YES (Done)',
                showsUserInterface: false,
                cancelNotification: true,
              ),
              AndroidNotificationAction(
                'NO_ACTION',
                'NO (Remind in 3h)',
                showsUserInterface: false,
                cancelNotification: true,
              ),
            ] : null,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time, // This makes it repeat daily
      );
      LogService().log('  - SUCCESS: Daily reminder scheduled');
    } catch (e) {
      LogService().error('  - FAILED to schedule daily reminder', e);
    }
  }


  Future<void> cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
    LogService().log('Cancelled notification for Task $id');
  }
}
