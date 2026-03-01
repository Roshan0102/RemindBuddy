import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'gold_price_service.dart';
import 'storage_service.dart';
import 'notification_service.dart';
import 'log_service.dart';

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

  /// Schedule both 11 AM and 7 PM daily alarms
  Future<void> scheduleGoldPriceFetching() async {
    // Cancel any existing alarms first
    await cancelAllAlarms();

    // Schedule 11 AM alarm
    final morning11AM = _getNextScheduledTime(11, 0);
    await AndroidAlarmManager.oneShotAt(
      morning11AM,
      morningAlarmId,
      _morningFetchCallback,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
    );
    print('✅ Scheduled 11 AM gold price fetch for $morning11AM');

    // Schedule 7 PM alarm
    final evening7PM = _getNextScheduledTime(19, 0);
    await AndroidAlarmManager.oneShotAt(
      evening7PM,
      eveningAlarmId,
      _eveningFetchCallback,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
    );
    print('✅ Scheduled 7 PM gold price fetch for $evening7PM');
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
      
      final goldService = GoldPriceService();
      final storageService = StorageService();
      final notificationService = NotificationService();

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
      final now = DateTime.now();
      var nextMorning = DateTime(now.year, now.month, now.day, 11, 0);
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
      LogService.staticLog('✅ Rescheduled next 11 AM fetch for $nextMorning');
    }
  }

  /// Evening fetch callback (7 PM)
  /// This only updates if the price has changed from the morning
  @pragma('vm:entry-point')
  static Future<void> _eveningFetchCallback() async {
    try {
      LogService.staticLog('🌆 7 PM Gold Price Fetch Started');
      
      final goldService = GoldPriceService();
      final storageService = StorageService();
      final notificationService = NotificationService();

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
      final now = DateTime.now();
      var nextEvening = DateTime(now.year, now.month, now.day, 19, 0);
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
      LogService.staticLog('✅ Rescheduled next 7 PM fetch for $nextEvening');
    }
  }

  /// Manual fetch for testing
  Future<void> manualFetch() async {
    LogService.staticLog('🔄 Manual gold price fetch triggered');
    await _morningFetchCallback();
  }
}
