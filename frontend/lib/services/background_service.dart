import 'package:workmanager/workmanager.dart';
import '../models/gold_price.dart'; // Import model
import 'gold_price_service.dart';
import 'storage_service.dart';
import 'notification_service.dart';
import 'log_service.dart';

// Task Name
const String fetchGoldTask = "fetchGoldPriceTask";

/// Top-level function for Workmanager
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    LogService.staticLog("Workmanager Task Started: $task");

    if (task == fetchGoldTask) {
      try {
        final goldService = GoldPriceService();
        final storageService = StorageService();
        final notificationService = NotificationService();

        // 1. Fetch current price
        final result = await goldService.checkAndNotifyGoldPriceChange();
        
        if (result != null) {
          final GoldPrice newPrice = result['price'] as GoldPrice;
           
           LogService.staticLog("New Price Fetched: ${newPrice.price}");
           
           // 2. Get Previous Price for Diff
           // We need to await DB init inside StorageService, which is handled by getter
           final double? previousPrice = await storageService.getPreviousGoldPrice();
           
           double? diff;
           if (previousPrice != null) {
             diff = newPrice.price - previousPrice;
             LogService.staticLog("Price Difference: $diff");
           }
           
           // 3. Save New Price
           await storageService.saveGoldPrice(newPrice);
           
           // 4. Notify
           await notificationService.showGoldPriceNotification(newPrice.price, diff);
        }
      } catch (e) {
        LogService.staticLog("Error in background task: $e");
        // We return true so it doesn't retry infinitely if it's a code logical error, 
        // but false if it's a network error? 
        // For simplicity, return true to acknowledge execution.
        return Future.value(true);
      }
    }
    
    return Future.value(true);
  });
}

class BackgroundService {
  static final BackgroundService _instance = BackgroundService._internal();
  factory BackgroundService() => _instance;
  BackgroundService._internal();

  Future<void> init() async {
    await Workmanager().initialize(
      callbackDispatcher,
    );
    // Workmanager().initialize(..., isInDebugMode: true) // Deprecated and no longer functional in newer versions often.
    // Use system notification logging instead.
    print("Workmanager Initialized");
  }

  Future<void> registerPeriodicTask() async {
    // Schedule periodic task
    // Note: Android minimum interval is 15 minutes.
    // For 11AM and 7PM specifically, we would typically use AlarmManager, 
    // but Workmanager is safer for background execution constraints.
    // We will run it every 4 hours to catch the updates reasonably close to the time.
    await Workmanager().registerPeriodicTask(
      "gold_price_periodic",
      fetchGoldTask,
      frequency: const Duration(hours: 4), 
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      initialDelay: const Duration(minutes: 15),
    );
    print("Periodic Task Registered");
  }
}
