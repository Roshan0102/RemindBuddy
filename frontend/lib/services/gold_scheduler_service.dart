import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'gold_price_service.dart';
import 'storage_service.dart';
import 'notification_service.dart';
import 'log_service.dart';
import 'shift_service.dart';
import '../models/gold_price.dart';

/// Scheduled Gold Price Fetcher & Shift Reminder (BACKUP mechanism)
/// 
/// NOTE: The PRIMARY mechanism is now ForegroundTaskService.
/// This alarm-based approach is kept as a BACKUP in case the foreground 
/// service is stopped by the user. It uses AndroidAlarmManager which
/// can be unreliable on some OEM ROMs (Vivo/iQOO/Xiaomi etc).
class GoldSchedulerService {
  static final GoldSchedulerService _instance = GoldSchedulerService._internal();
  factory GoldSchedulerService() => _instance;
  GoldSchedulerService._internal();

  // Alarm IDs
  static const int morningAlarmId = 11000;
  static const int eveningAlarmId = 12000;
  static const int shiftAlarmId = 13000;

  /// Initialize
  Future<void> init() async {
    await AndroidAlarmManager.initialize();
    LogService().log('✅ Gold & Shift Scheduler Initialized (BACKUP alarms)');
  }

  /// Schedule the background fetching alarms (BACKUP)
  Future<void> scheduleGoldPriceFetching() async {
    await cancelAllAlarms();

    final now = DateTime.now();
    
    // 1. Morning Alarm (11:00 AM)
    DateTime morningTime = DateTime(now.year, now.month, now.day, 11, 0);
    if (morningTime.isBefore(now)) {
      morningTime = morningTime.add(const Duration(days: 1));
    }
    
    await AndroidAlarmManager.oneShotAt(
      morningTime,
      morningAlarmId,
      goldMorningCallback,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
    );
    LogService().log('✅ [BACKUP] Scheduled Gold Morning fetch for: $morningTime');

    // 2. Evening Alarm (7:00 PM)
    DateTime eveningTime = DateTime(now.year, now.month, now.day, 19, 0);
    if (eveningTime.isBefore(now)) {
      eveningTime = eveningTime.add(const Duration(days: 1));
    }
    
    await AndroidAlarmManager.oneShotAt(
      eveningTime,
      eveningAlarmId,
      goldEveningCallback,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
    );
    LogService().log('✅ [BACKUP] Scheduled Gold Evening fetch for: $eveningTime');

    // 3. Shift Alarm (10:00 PM)
    DateTime shiftTime = DateTime(now.year, now.month, now.day, 22, 0);
    if (shiftTime.isBefore(now)) {
      shiftTime = shiftTime.add(const Duration(days: 1));
    }

    await AndroidAlarmManager.oneShotAt(
      shiftTime,
      shiftAlarmId,
      shiftDailyCallback,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
    );
    LogService().log('✅ [BACKUP] Scheduled Shift Daily trigger for: $shiftTime');
  }

  /// Cancel all alarms
  Future<void> cancelAllAlarms() async {
    await AndroidAlarmManager.cancel(morningAlarmId);
    await AndroidAlarmManager.cancel(eveningAlarmId);
    await AndroidAlarmManager.cancel(shiftAlarmId);
    print('🗑️ Background Alarms Cancelled');
  }

  /// Test fetch (forces immediate background execution)
  Future<void> manualFetch() async {
    LogService().log('🔄 Testing background gold fetch...');
    await AndroidAlarmManager.oneShot(
      const Duration(seconds: 1),
      morningAlarmId + 999,
      goldMorningCallback,
      exact: true,
      wakeup: true,
    );
  }
}

/// Static entry points for Android Alarm Manager (BACKUP)
@pragma('vm:entry-point')
void goldMorningCallback() async {
  LogService.staticLog('[BACKUP_ALARM] Morning gold callback triggered');
  await _performGoldFetch('11 AM');
  
  // Reschedule for tomorrow
  final now = DateTime.now();
  final next = DateTime(now.year, now.month, now.day, 11, 0).add(const Duration(days: 1));
  await AndroidAlarmManager.oneShotAt(
    next,
    GoldSchedulerService.morningAlarmId,
    goldMorningCallback,
    exact: true,
    wakeup: true,
    rescheduleOnReboot: true,
  );
}

@pragma('vm:entry-point')
void goldEveningCallback() async {
  LogService.staticLog('[BACKUP_ALARM] Evening gold callback triggered');
  await _performGoldFetch('7 PM');

  // Reschedule for tomorrow
  final now = DateTime.now();
  final next = DateTime(now.year, now.month, now.day, 19, 0).add(const Duration(days: 1));
  await AndroidAlarmManager.oneShotAt(
    next,
    GoldSchedulerService.eveningAlarmId,
    goldEveningCallback,
    exact: true,
    wakeup: true,
    rescheduleOnReboot: true,
  );
}

@pragma('vm:entry-point')
void shiftDailyCallback() async {
  LogService.staticLog('[BACKUP_ALARM] Shift daily callback triggered');
  LogService.staticLog('📅 Triggering Dynamic Shift Update (10 PM Task)');
  try {
     await Firebase.initializeApp();
     final shiftService = ShiftService();
     await shiftService.showShiftNotification();
  } catch (e) {
     LogService.staticLog('❌ Error in shift callback: $e');
  }

  // Reschedule for tomorrow
  final now = DateTime.now();
  final next = DateTime(now.year, now.month, now.day, 22, 0).add(const Duration(days: 1));
  await AndroidAlarmManager.oneShotAt(
    next,
    GoldSchedulerService.shiftAlarmId,
    shiftDailyCallback,
    exact: true,
    wakeup: true,
    rescheduleOnReboot: true,
  );
}

/// Core fetch logic shared by both callbacks (BACKUP)
Future<void> _performGoldFetch(String timeLabel) async {
  LogService.staticLog('🌕 [BACKUP] Starting Background Gold Fetch ($timeLabel)');
  
  try {
    // 1. Initialize Firebase (CRITICAL for background isolates)
    await Firebase.initializeApp();
    
    // 2. Init Services
    final notificationService = NotificationService();
    await notificationService.init();
    
    final goldService = GoldPriceService();
    final storage = StorageService();

    // 3. Fetch Price
    final result = await goldService.fetchCurrentGoldPrice();
    final newPrice = result['price'] as GoldPrice?;
    
    if (newPrice != null) {
      LogService.staticLog('💰 [BACKUP] Gold Price Fetched: ₹${newPrice.price}');
      
      // 4. Get Latest Price for Change Calculation
      final prevPrice = await storage.getLatestGoldPrice();
      double change = 0.0;
      if (prevPrice != null) {
        change = newPrice.price - prevPrice.price;
        LogService.staticLog('🔍 [BACKUP] Price comparison: ${newPrice.price} vs ${prevPrice.price}');
      }
      
      // Update price change in the model
      final updatedPrice = GoldPrice(
        date: newPrice.date,
        timestamp: newPrice.timestamp,
        price: newPrice.price,
        priceChange: change,
      );

      // 5. Save to DB
      await storage.saveGoldPrice(updatedPrice);
      
      // 6. Show Notification with Price
      String changeText = "";
      if (change != 0.0) {
        String sign = change > 0 ? "+" : "-";
        String emoji = change > 0 ? "📈" : "📉";
        changeText = " ($emoji $sign₹${change.abs().toStringAsFixed(0)})";
      }

      await notificationService.flutterLocalNotificationsPlugin.show(
        8000,
        '💰 Gold Price Update ($timeLabel)',
        'Today: ₹${newPrice.price.toStringAsFixed(0)}$changeText',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'gold_price_channel',
            'Gold Price Alerts',
            channelDescription: 'Daily gold price updates',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            icon: '@mipmap/ic_launcher',
          ),
        ),
        payload: 'gold_tab',
      );
      
      LogService.staticLog('✅ [BACKUP] Gold background task finished successfully');
    } else {
      LogService.staticLog('⚠️ [BACKUP] Gold fetch failed: ${result['method']} - ${result['debug']}');
      
      await notificationService.flutterLocalNotificationsPlugin.show(
        8001,
        '⚠️ Gold Rate Sync Issue',
        'Could not update prices automatically. Open app to retry.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'gold_price_channel',
            'Gold Price Alerts',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        payload: 'gold_tab',
      );
    }
  } catch (e) {
    LogService.staticLog('❌ [BACKUP] Fatal error in gold fetch task: $e');
  }
}
