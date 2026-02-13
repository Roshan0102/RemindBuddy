import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:intl/intl.dart';
import '../models/shift.dart';
import 'storage_service.dart';
import 'notification_service.dart';
import 'log_service.dart';

class ShiftService {
  static final ShiftService _instance = ShiftService._internal();
  factory ShiftService() => _instance;
  ShiftService._internal();

  final StorageService _storage = StorageService();
  final NotificationService _notificationService = NotificationService();

  // Schedule daily shift notification at specified time (default 10 PM)
  Future<void> scheduleDailyShiftNotification({int hour = 22, int minute = 0}) async {
    try {
      await _notificationService.flutterLocalNotificationsPlugin.zonedSchedule(
        9999, // Unique ID for daily shift notification
        'Tomorrow\'s Shift',
        'Loading shift information...',
        _nextInstanceOfTime(hour, minute),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'shift_reminder_channel',
            'Shift Reminders',
            channelDescription: 'Daily notifications about upcoming shifts',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );

      LogService().log('Daily shift notification scheduled for $hour:$minute');
    } catch (e) {
      LogService().error('Failed to schedule daily shift notification', e);
    }
  }

  // Get next instance of specified time
  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    return scheduledDate;
  }

  // Show immediate notification with shift info
  Future<void> showShiftNotification() async {
    try {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final dayAfterTomorrow = DateTime.now().add(const Duration(days: 2));

      final tomorrowDate = DateFormat('yyyy-MM-dd').format(tomorrow);
      final dayAfterDate = DateFormat('yyyy-MM-dd').format(dayAfterTomorrow);

      final tomorrowShift = await _storage.getShiftForDate(tomorrowDate);
      final dayAfterShift = await _storage.getShiftForDate(dayAfterDate);

      if (tomorrowShift == null) {
        LogService().log('No shift data found for tomorrow');
        return;
      }

      final tomorrowShiftObj = Shift.fromMap(tomorrowShift);
      String message = _formatShiftMessage('Tomorrow', tomorrowShiftObj);

      if (dayAfterShift != null) {
        final dayAfterShiftObj = Shift.fromMap(dayAfterShift);
        message += ' | ${_formatShiftMessage(DateFormat('EEEE').format(dayAfterTomorrow), dayAfterShiftObj)}';
      }

      await _notificationService.flutterLocalNotificationsPlugin.show(
        9999,
        '📅 Upcoming Shifts',
        message,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'shift_reminder_channel',
            'Shift Reminders',
            channelDescription: 'Daily notifications about upcoming shifts',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
        ),
      );

      LogService().log('Shift notification shown: $message');
    } catch (e) {
      LogService().error('Failed to show shift notification', e);
    }
  }

  String _formatShiftMessage(String day, Shift shift) {
    if (shift.isWeekOff) {
      return '$day: Week Off 🎉';
    }
    
    String emoji = '';
    switch (shift.shiftType) {
      case 'morning':
        emoji = '🌅';
        break;
      case 'afternoon':
        emoji = '☀️';
        break;
      case 'night':
        emoji = '🌙';
        break;
    }
    
    return '$day: $emoji ${shift.getDisplayName()} (${shift.getTimeRange()})';
  }

  // Schedule Amla reminder 5 minutes after shift start
  Future<void> scheduleAmlaReminder(Shift shift, DateTime shiftDate) async {
    if (shift.isWeekOff || shift.startTime == null) return;

    try {
      // Parse start time
      final timeParts = shift.startTime!.split(':');
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);

      // Schedule for 5 minutes after shift start
      final reminderTime = DateTime(
        shiftDate.year,
        shiftDate.month,
        shiftDate.day,
        hour,
        minute,
      ).add(const Duration(minutes: 5));

      // Only schedule if it's in the future
      if (reminderTime.isAfter(DateTime.now())) {
        final tzReminderTime = tz.TZDateTime.from(reminderTime, tz.local);

        await _notificationService.flutterLocalNotificationsPlugin.zonedSchedule(
          10000 + shiftDate.day, // Unique ID per day
          '🍋 Shopping Reminder',
          'Don\'t forget to buy Amla!',
          tzReminderTime,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'amla_reminder_channel',
              'Amla Reminders',
              channelDescription: 'Reminders to buy Amla after shift starts',
              importance: Importance.high,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );

        LogService().log('Amla reminder scheduled for ${DateFormat('yyyy-MM-dd HH:mm').format(reminderTime)}');
      }
    } catch (e) {
      LogService().error('Failed to schedule Amla reminder', e);
    }
  }

  // Schedule all Amla reminders for upcoming shifts
  Future<void> scheduleAllAmlaReminders() async {
    try {
      final upcomingShifts = await _storage.getUpcomingShifts(30); // Next 30 days

      for (var shiftMap in upcomingShifts) {
        final shift = Shift.fromMap(shiftMap);
        final shiftDate = DateTime.parse(shift.date);
        await scheduleAmlaReminder(shift, shiftDate);
      }

      LogService().log('Scheduled Amla reminders for ${upcomingShifts.length} upcoming shifts');
    } catch (e) {
      LogService().error('Failed to schedule all Amla reminders', e);
    }
  }

  // Cancel all shift-related notifications
  Future<void> cancelAllShiftNotifications() async {
    try {
      // Cancel daily shift notification
      await _notificationService.flutterLocalNotificationsPlugin.cancel(9999);

      // Cancel Amla reminders (IDs 10000-10031 for 31 days)
      for (int i = 10000; i < 10032; i++) {
        await _notificationService.flutterLocalNotificationsPlugin.cancel(i);
      }

      LogService().log('Cancelled all shift notifications');
    } catch (e) {
      LogService().error('Failed to cancel shift notifications', e);
    }
  }

  // Get shift change alert message
  String? getShiftChangeAlert(Shift currentShift, Shift nextShift) {
    if (currentShift.isWeekOff || nextShift.isWeekOff) return null;
    if (currentShift.shiftType == nextShift.shiftType) return null;

    // Detect problematic transitions
    if (currentShift.shiftType == 'night' && nextShift.shiftType == 'morning') {
      return '⚠️ Alert: Night shift followed by morning shift! Set an early alarm.';
    }

    if (currentShift.shiftType == 'morning' && nextShift.shiftType == 'night') {
      return '⚠️ Alert: Shift change from morning to night. Adjust your sleep schedule.';
    }

    return 'ℹ️ Shift change: ${currentShift.getDisplayName()} → ${nextShift.getDisplayName()}';
  }
}
