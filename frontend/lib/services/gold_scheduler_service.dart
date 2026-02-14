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
    await AndroidAlarmManager.periodic(
      const Duration(days: 1),
      morningAlarmId,
      _morningFetchCallback,
      startAt: morning11AM,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
    );
    print('✅ Scheduled 11 AM gold price fetch');

    // Schedule 7 PM alarm
    final evening7PM = _getNextScheduledTime(19, 0);
    await AndroidAlarmManager.periodic(
      const Duration(days: 1),
      eveningAlarmId,
      _eveningFetchCallback,
      startAt: evening7PM,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
    );
    print('✅ Scheduled 7 PM gold price fetch');
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
      final newPrice = await goldService.fetchCurrentGoldPrice();
      
      if (newPrice != null) {
        LogService.staticLog('💰 11 AM Price Fetched: ₹${newPrice.price22k}');
        
        // Get previous price for comparison
        final previousPrice = await storageService.getPreviousGoldPrice();
        
        double? diff;
        if (previousPrice != null) {
          diff = newPrice.price22k - previousPrice;
        }
        
        // Always save the 11 AM price
        await storageService.saveGoldPrice(newPrice);
        LogService.staticLog('✅ 11 AM Price saved to database');
        
        // Send notification
        await notificationService.showGoldPriceNotification(
          newPrice.price22k,
          diff,
          time: '11 AM',
        );
      } else {
        LogService.staticLog('❌ Failed to fetch 11 AM price');
      }
    } catch (e) {
      LogService.staticLog('❌ Error in 11 AM fetch: $e');
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
      final newPrice = await goldService.fetchCurrentGoldPrice();
      
      if (newPrice != null) {
        LogService.staticLog('💰 7 PM Price Fetched: ₹${newPrice.price22k}');
        
        // Get the latest price from database (should be from 11 AM today)
        final latestPrice = await storageService.getLatestGoldPrice();
        
        if (latestPrice != null) {
          final priceDiff = (newPrice.price22k - latestPrice.price22k).abs();
          
          // Only save if price has changed (tolerance of ₹1 to avoid minor fluctuations)
          if (priceDiff > 1.0) {
            LogService.staticLog('📈 Price changed by ₹$priceDiff - Saving new entry');
            
            await storageService.saveGoldPrice(newPrice);
            
            // Send notification about the change
            await notificationService.showGoldPriceNotification(
              newPrice.price22k,
              newPrice.price22k - latestPrice.price22k,
              time: '7 PM',
            );
          } else {
            LogService.staticLog('✓ Price unchanged at 7 PM - No new entry added');
          }
        } else {
          // No previous price, save this one
          await storageService.saveGoldPrice(newPrice);
          LogService.staticLog('✅ First 7 PM price saved');
        }
      } else {
        LogService.staticLog('❌ Failed to fetch 7 PM price');
      }
    } catch (e) {
      LogService.staticLog('❌ Error in 7 PM fetch: $e');
    }
  }

  /// Manual fetch for testing
  Future<void> manualFetch() async {
    LogService.staticLog('🔄 Manual gold price fetch triggered');
    await _morningFetchCallback();
  }
}
