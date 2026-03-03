import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'gold_price_service.dart';
import 'storage_service.dart';
import 'notification_service.dart';
import 'log_service.dart';
import 'auth_service.dart';

/// Scheduled Gold Price Fetcher
/// Fetches gold prices at 11 AM and 7 PM IST daily
class GoldSchedulerService {
  static final GoldSchedulerService _instance = GoldSchedulerService._internal();
  factory GoldSchedulerService() => _instance;
  GoldSchedulerService._internal();

  // Alarm IDs
  static const int morningNotifyId = 11000;
  static const int eveningNotifyId = 12000;

  /// Initialize
  Future<void> init() async {
    // We still initialize AlarmManager just in case we use it for actual background work,
    // but the notifications will follow the ShiftService method.
    await AndroidAlarmManager.initialize();
    print('✅ Gold Scheduler Initialized');
  }

  /// Schedule both morning and evening notifications (Shift Method)
  Future<void> scheduleGoldPriceFetching() async {
    // Cancel any existing alarms/notifications first
    await cancelAllAlarms();

    final notificationService = NotificationService();
    final now = DateTime.now();
    
    // Schedule for the next 45 days (Shift Method: zonedSchedule for 45 days)
    for (int i = 0; i < 45; i++) {
      final targetDate = now.add(Duration(days: i));
      
      // 11 AM Morning Notification
      final tz.TZDateTime morningDate = tz.TZDateTime(
        tz.local, targetDate.year, targetDate.month, targetDate.day, 11, 0,
      );
      
      // 7 PM Evening Notification
      final tz.TZDateTime eveningDate = tz.TZDateTime(
        tz.local, targetDate.year, targetDate.month, targetDate.day, 19, 0,
      );

      final tz.TZDateTime tzNow = tz.TZDateTime.now(tz.local);

      // Schedule Morning
      if (morningDate.isAfter(tzNow.add(const Duration(seconds: 5)))) {
        await notificationService.flutterLocalNotificationsPlugin.zonedSchedule(
          morningNotifyId + i,
          '💰 Gold Price Update (11 AM)',
          'Tap to check the latest gold rate for today.',
          morningDate,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'gold_price_channel',
              'Gold Price Alerts',
              channelDescription: 'Scheduled notifications for gold price updates',
              importance: Importance.high,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: 'gold_tab',
        );
      }

      // Schedule Evening
      if (eveningDate.isAfter(tzNow.add(const Duration(seconds: 5)))) {
        await notificationService.flutterLocalNotificationsPlugin.zonedSchedule(
          eveningNotifyId + i,
          '💰 Gold Price Update (7 PM)',
          'Tap to check the latest gold rate for today.',
          eveningDate,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'gold_price_channel',
              'Gold Price Alerts',
              channelDescription: 'Scheduled notifications for gold price updates',
              importance: Importance.high,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: 'gold_tab',
        );
      }
    }

    LogService().log('✅ Scheduled 45 days of gold price notifications at 11 AM & 7 PM');
  }

  /// Cancel all scheduled notifications
  Future<void> cancelAllAlarms() async {
    final notificationService = NotificationService();
    for (int i = 0; i < 45; i++) {
      await notificationService.flutterLocalNotificationsPlugin.cancel(morningNotifyId + i);
      await notificationService.flutterLocalNotificationsPlugin.cancel(eveningNotifyId + i);
    }
    print('🗑️ Cancelled all gold price scheduled notifications');
  }

  /// Manual fetch for testing
  Future<void> manualFetch() async {
    LogService.staticLog('🔄 Manual gold price fetch triggered');
    // Implement manual fetch logic if needed, or just let the screen handle it
  }
}
