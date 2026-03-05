import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'gold_price_service.dart';
import 'storage_service.dart';
import 'notification_service.dart';
import 'log_service.dart';
import 'auth_service.dart';
import '../models/gold_price.dart';

/// Scheduled Gold Price Fetcher
/// Actually fetches the price in the background at 11 AM and 7 PM
class GoldSchedulerService {
  static final GoldSchedulerService _instance = GoldSchedulerService._internal();
  factory GoldSchedulerService() => _instance;
  GoldSchedulerService._internal();

  // Alarm IDs
  static const int morningAlarmId = 11000;
  static const int eveningAlarmId = 12000;

  /// Initialize
  Future<void> init() async {
    await AndroidAlarmManager.initialize();
    LogService().log('✅ Gold Scheduler (Background Feed) Initialized');
  }

  /// Schedule the background fetching alarms
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
    print('✅ Scheduled morning fetch for: $morningTime');

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
    print('✅ Scheduled evening fetch for: $eveningTime');
  }

  /// Cancel both alarms
  Future<void> cancelAllAlarms() async {
    await AndroidAlarmManager.cancel(morningAlarmId);
    await AndroidAlarmManager.cancel(eveningAlarmId);
    print('🗑️ Gold Alarms Cancelled');
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

/// Static entry points for Android Alarm Manager
@pragma('vm:entry-point')
void goldMorningCallback() async {
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

/// Core fetch logic shared by both callbacks
Future<void> _performGoldFetch(String timeLabel) async {
  LogService.staticLog('🌕 Starting Background Gold Fetch ($timeLabel)');
  
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
      LogService.staticLog('💰 Gold Price Fetched: ₹${newPrice.price}');
      
      // 4. Get Previous Price for Change Calculation
      final prevPrice = await storage.getLatestGoldPrice();
      double change = 0.0;
      if (prevPrice != null) {
        change = newPrice.price - prevPrice.price;
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
        changeText = change > 0 ? " (📈 +₹${change.abs().toStringAsFixed(0)})" : " (📉 -₹${change.abs().toStringAsFixed(0)})";
      }

      await notificationService.flutterLocalNotificationsPlugin.show(
        8000,
        '💰 Gold Price Update ($timeLabel)',
        'Latest price: ₹${newPrice.price.toStringAsFixed(0)}$changeText',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'gold_price_channel',
            'Gold Price Alerts',
            channelDescription: 'Daily gold price updates',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
          ),
        ),
        payload: 'gold_tab',
      );
      
      LogService.staticLog('✅ Gold background task finished successfully');
    } else {
      LogService.staticLog('⚠️ Gold fetch failed: ${result['debug']}');
      // Optional: notify even on failure?
      await notificationService.flutterLocalNotificationsPlugin.show(
        8000,
        '⚠️ Gold Fetch Issue ($timeLabel)',
        'Check internet connection to update gold prices.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'gold_price_channel',
            'Gold Price Alerts',
            importance: Importance.low,
          ),
        ),
        payload: 'gold_tab',
      );
    }
  } catch (e) {
    LogService.staticLog('❌ Fatal error in gold fetch task: $e');
  }
}
