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
  static const int morningAlarmId = 1001;
  static const int eveningAlarmId = 1002;

  /// Initialize the alarm manager
  Future<void> init() async {
    await AndroidAlarmManager.initialize();
    print('✅ Gold Scheduler Initialized');
  }

  /// Schedule both morning and evening alarms
  Future<void> scheduleGoldPriceFetching() async {
    // Cancel any existing alarms first
    await cancelAllAlarms();

    final prefs = await SharedPreferences.getInstance();
    final morningHour = prefs.getInt('gold_morning_hour') ?? 11;
    final morningMinute = prefs.getInt('gold_morning_minute') ?? 0;
    final eveningHour = prefs.getInt('gold_evening_hour') ?? 19;
    final eveningMinute = prefs.getInt('gold_evening_minute') ?? 0;

    // Schedule morning alarm
    final morningTime = _getNextScheduledTime(morningHour, morningMinute);
    await AndroidAlarmManager.oneShotAt(
      morningTime,
      morningAlarmId,
      _morningFetchCallback,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
    );
    print('✅ Scheduled morning gold price fetch for $morningTime');

    // Schedule evening alarm
    final eveningTime = _getNextScheduledTime(eveningHour, eveningMinute);
    await AndroidAlarmManager.oneShotAt(
      eveningTime,
      eveningAlarmId,
      _eveningFetchCallback,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
    );
    print('✅ Scheduled evening gold price fetch for $eveningTime');
  }

  /// Cancel all scheduled alarms
  Future<void> cancelAllAlarms() async {
    await AndroidAlarmManager.cancel(morningAlarmId);
    await AndroidAlarmManager.cancel(eveningAlarmId);
    print('🗑️ Cancelled all gold price alarms');
  }

  /// Get next scheduled time for a given hour and minute
  DateTime _getNextScheduledTime(int hour, int minute) {
    final now = DateTime.now();
    var scheduled = DateTime(now.year, now.month, now.day, hour, minute);
    
    // If the time has already passed today, schedule for tomorrow
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    
    return scheduled;
  }

  /// Morning fetch callback (11 AM)
  /// This always updates the price in the database
  @pragma('vm:entry-point')
  static Future<void> _morningFetchCallback() async {
    try {
      LogService.staticLog('🌅 11 AM Gold Price Fetch Started');
      
      // Essential: Initialize Firebase and Notification Service in the background isolate
      await Firebase.initializeApp();
      final notificationService = NotificationService();
      await notificationService.init();

      final goldService = GoldPriceService();
      final storageService = StorageService();

      // Fetch current price
      final result = await goldService.fetchCurrentGoldPrice();
      final newPrice = result['price'];
      final method = result['method'];
      final debug = result['debug'];
      
      LogService.staticLog('📊 Fetch method: $method');
      LogService.staticLog('🔍 Debug: $debug');
      
        if (newPrice != null) {
        LogService.staticLog('💰 11 AM Price Fetched: ₹${newPrice.price}');
        
        // Always save the 11 AM price (which also updates time and calculates change)
        await storageService.saveGoldPrice(newPrice);
        LogService.staticLog('✅ 11 AM Price saved to database');
        
        try {
          await AuthService().init();
          LogService.staticLog('✅ 11 AM Authentication Initiated');
        } catch(e) {
          LogService.staticLog('❌ Failed Authentication: $e');
        }
        
        // Re-fetch to get calculated diff
        final savedPrice = await storageService.getLatestGoldPrice();
        
        // Send notification
        await notificationService.showGoldPriceNotification(
          newPrice.price,
          savedPrice?.priceChange,
          time: '11 AM',
        );
      } else {
        LogService.staticLog('❌ Failed to fetch 11 AM price');
      }
    } catch (e) {
      LogService.staticLog('❌ Error in 11 AM fetch: $e');
    } finally {
      // Reschedule for next day (recursive oneShot for better reliability)
      final prefs = await SharedPreferences.getInstance();
      final morningHour = prefs.getInt('gold_morning_hour') ?? 11;
      final morningMinute = prefs.getInt('gold_morning_minute') ?? 0;
      
      final now = DateTime.now();
      var nextMorning = DateTime(now.year, now.month, now.day, morningHour, morningMinute);
      if (nextMorning.isBefore(now) || nextMorning.isAtSameMomentAs(now)) {
        nextMorning = nextMorning.add(const Duration(days: 1));
      }
      await AndroidAlarmManager.oneShotAt(
        nextMorning,
        morningAlarmId,
        _morningFetchCallback,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: true,
      );
      LogService.staticLog('✅ Rescheduled next morning fetch for $nextMorning');
    }
  }

  /// Evening fetch callback (7 PM)
  /// This only updates if the price has changed from the morning
  @pragma('vm:entry-point')
  static Future<void> _eveningFetchCallback() async {
    try {
      LogService.staticLog('🌆 7 PM Gold Price Fetch Started');
      
      // Essential: Initialize Firebase and Notification Service in the background isolate
      await Firebase.initializeApp();
      final notificationService = NotificationService();
      await notificationService.init();

      final goldService = GoldPriceService();
      final storageService = StorageService();

      // Fetch current price
      final result = await goldService.fetchCurrentGoldPrice();
      final newPrice = result['price'];
      final method = result['method'];
      final debug = result['debug'];
      
      LogService.staticLog('📊 Fetch method: $method');
      LogService.staticLog('🔍 Debug: $debug');
      
      if (newPrice != null) {
        LogService.staticLog('💰 7 PM Price Fetched: ₹${newPrice.price}');
        
        // Always save the 7 PM price (updates time, stores new price)
        await storageService.saveGoldPrice(newPrice);
        LogService.staticLog('✅ 7 PM Price saved to database');
        
        try {
          await AuthService().init();
          LogService.staticLog('✅ 7 PM Authentication Initiated');
        } catch(e) {
          LogService.staticLog('❌ Failed Authentication: $e');
        }
        
        // Re-fetch to get calculated diff
        final savedPrice = await storageService.getLatestGoldPrice();
        
        // Send notification about the fetch
        await notificationService.showGoldPriceNotification(
          newPrice.price,
          savedPrice?.priceChange,
          time: '7 PM',
        );
      } else {
        LogService.staticLog('❌ Failed to fetch 7 PM price');
      }
    } catch (e) {
      LogService.staticLog('❌ Error in 7 PM fetch: $e');
    } finally {
      // Reschedule for next day
      final prefs = await SharedPreferences.getInstance();
      final eveningHour = prefs.getInt('gold_evening_hour') ?? 19;
      final eveningMinute = prefs.getInt('gold_evening_minute') ?? 0;
      
      final now = DateTime.now();
      var nextEvening = DateTime(now.year, now.month, now.day, eveningHour, eveningMinute);
      if (nextEvening.isBefore(now) || nextEvening.isAtSameMomentAs(now)) {
        nextEvening = nextEvening.add(const Duration(days: 1));
      }
      await AndroidAlarmManager.oneShotAt(
        nextEvening,
        eveningAlarmId,
        _eveningFetchCallback,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: true,
      );
      LogService.staticLog('✅ Rescheduled next evening fetch for $nextEvening');
    }
  }

  /// Manual fetch for testing
  Future<void> manualFetch() async {
    LogService.staticLog('🔄 Manual gold price fetch triggered');
    await _morningFetchCallback();
  }
}
