import 'package:workmanager/workmanager.dart';
import '../models/gold_price.dart';
import 'gold_price_service.dart';
import 'storage_service.dart';
import 'notification_service.dart';
import 'log_service.dart';
import 'auth_service.dart';
import 'package:firebase_core/firebase_core.dart';

// Task Names
const String fetchGoldTask = "fetchGoldPriceTask";
const String healthCheckTask = "appHealthCheckTask";

/// Top-level function for Workmanager
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    LogService.staticLog("🔧 Workmanager Triggered: $task");

    try {
      if (task == fetchGoldTask || task == Workmanager.iOSBackgroundTask) {
        await _handleGoldFetch();
      } else if (task == healthCheckTask) {
        // App health check could ensure Alarms are still scheduled
        // But alarms are reset on reboot, so we don't need much here
        LogService.staticLog("App Health check OK");
      }
    } catch (e) {
      LogService.staticLog("❌ Error in background task: $e");
    }
    
    return Future.value(true);
  });
}

Future<void> _handleGoldFetch() async {
  try {
    await Firebase.initializeApp();
    final goldService = GoldPriceService();
    final storageService = StorageService();
    final notificationService = NotificationService();

    // 1. Fetch current price
    final result = await goldService.fetchCurrentGoldPrice();
    final newPrice = result['price'] as GoldPrice?;
    
    if (newPrice != null) {
       LogService.staticLog("💰 Workmanager fetched: ${newPrice.price}");
       
       final previousPrice = await storageService.getPreviousGoldPrice();
       double? diff;
       if (previousPrice != null) {
         diff = newPrice.price - previousPrice;
       }
       
       // Update price change in the model
       final updatedPrice = GoldPrice(
         date: newPrice.date,
         timestamp: newPrice.timestamp,
         price: newPrice.price,
         priceChange: diff ?? 0.0,
       );

       await storageService.saveGoldPrice(updatedPrice);
       await notificationService.showGoldPriceNotification(newPrice.price, diff, time: 'Sync');
    }
  } catch (e) {
    LogService.staticLog("❌ Failed Gold Fetch in Workmanager: $e");
  }
}

class BackgroundService {
  static final BackgroundService _instance = BackgroundService._internal();
  factory BackgroundService() => _instance;
  BackgroundService._internal();

  Future<void> init() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );
    LogService().log('✅ Workmanager Initialized');
  }

  /// Register periodic task for gold price checking
  /// This acts as a fallback for the precise AlarmManager tasks
  Future<void> registerPeriodicTask() async {
    // Android minimum interval is 15 minutes.
    // We run it every 2 hours to ensure we don't miss updates and to stay alive.
    await Workmanager().registerPeriodicTask(
      "gold_price_resilience",
      fetchGoldTask,
      frequency: const Duration(hours: 2), 
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: false,
      ),
      initialDelay: const Duration(minutes: 30),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
    LogService().log("✅ Periodic Sync Task Registered (2h)");
  }
}
