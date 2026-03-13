// ForegroundTaskService - Reliable background execution using Android Foreground Service
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';
import 'gold_price_service.dart';
import 'storage_service.dart';

import 'shift_service.dart';
import 'log_service.dart';
import '../models/gold_price.dart';

/// Foreground Task Service - Uses Android Foreground Service for RELIABLE
/// background execution. This replaces the unreliable android_alarm_manager_plus
/// approach that fails when app is killed or phone is sleeping.
///
/// How it works:
/// 1. Starts a persistent foreground service (shows a small notification)
/// 2. Runs a periodic task every 3 minutes (for testing gold price)
/// 3. Checks if it's time for gold/shift notifications and fires them
/// 4. Survives app kill, phone sleep, and battery optimization
class ForegroundTaskService {
  static final ForegroundTaskService _instance = ForegroundTaskService._internal();
  factory ForegroundTaskService() => _instance;
  ForegroundTaskService._internal();

  /// Initialize the foreground task service
  void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'remindbuddy_foreground',
        channelName: 'RemindBuddy Background Service',
        channelDescription: 'Keeps gold price updates, shift reminders, and task notifications running reliably.',
        channelImportance: NotificationChannelImportance.LOW,
        // Low importance = no sound, appears in status bar only
        priority: NotificationPriority.LOW,
        // Don't alert on every repeat
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // *** TESTING: repeat every 3 minutes (180000 ms) ***
        eventAction: ForegroundTaskEventAction.repeat(180000),
        // Auto-restart on device boot
        autoRunOnBoot: true,
        // Auto-restart on app update
        autoRunOnMyPackageReplaced: true,
        // Keep CPU awake
        allowWakeLock: true,
        // Keep WiFi alive for network requests
        allowWifiLock: true,
      ),
    );
    LogService().log('✅ ForegroundTaskService initialized (3-min interval)');
  }

  /// Start the foreground service
  Future<ServiceRequestResult> startService() async {
    // Android 13+ requires notification permission for foreground services
    final NotificationPermission notificationPermission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      LogService().log('⚠️ Requesting notification permission for FG service...');
      await FlutterForegroundTask.requestNotificationPermission();
    }
    
    // Check battery optimization
    if (await FlutterForegroundTask.isIgnoringBatteryOptimizations == false) {
       LogService().log('⚠️ Battery optimization is active. FG service may be killed.');
       // We won't auto-popup here to avoid spamming the user, but we log it.
    }

    if (await FlutterForegroundTask.isRunningService) {
      LogService().log('🔄 Foreground service already running, restarting...');
      return FlutterForegroundTask.restartService();
    } else {
      LogService().log('▶️ Starting foreground service...');
      return FlutterForegroundTask.startService(
        serviceId: 888,
        serviceTypes: [ForegroundServiceTypes.dataSync],
        notificationTitle: 'RemindBuddy Active',
        notificationText: 'Monitoring gold prices, shifts & reminders',
        callback: startForegroundCallback,
      );
    }
  }

  /// Stop the foreground service
  Future<ServiceRequestResult> stopService() async {
    LogService().log('⏹️ Stopping foreground service...');
    return FlutterForegroundTask.stopService();
  }

  /// Check if service is running
  Future<bool> get isRunning => FlutterForegroundTask.isRunningService;
}

// ============================================================
// TOP-LEVEL CALLBACK (runs in background isolate)
// ============================================================

/// This MUST be a top-level function (not inside a class)
@pragma('vm:entry-point')
void startForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(RemindBuddyTaskHandler());
}

/// The actual task handler that runs in the foreground service isolate
class RemindBuddyTaskHandler extends TaskHandler {
  int _tickCount = 0;
  DateTime? _lastGoldFetchTime;
  DateTime? _lastShiftNotifyTime;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _log('🚀 ForegroundTask started (starter: ${starter.name}) at $timestamp');
    _log('📋 Will fetch gold price every 3 minutes for testing');

    // Initialize Firebase in the background isolate
    try {
      await Firebase.initializeApp();
      _log('✅ Firebase initialized in background isolate');
    } catch (e) {
      _log('⚠️ Firebase init error (may already be initialized): $e');
    }
  }

  /// Called every 3 minutes (180000 ms) as configured
  @override
  void onRepeatEvent(DateTime timestamp) async {
    _tickCount++;
    final timeStr = DateFormat('HH:mm:ss').format(timestamp);
    _log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    _log('🔔 TICK #$_tickCount at $timeStr');

    // ========== GOLD PRICE FETCH (every 3 min for testing) ==========
    await _performGoldPriceFetch(timestamp);

    // ========== SHIFT NOTIFICATION CHECK ==========
    await _checkAndSendShiftNotification(timestamp);

    // ========== Update foreground notification with status ==========
    FlutterForegroundTask.updateService(
      notificationTitle: 'RemindBuddy Active',
      notificationText: 'Last check: $timeStr | Tick #$_tickCount',
    );

    // Send data to main isolate (for UI debug)
    FlutterForegroundTask.sendDataToMain({
      'tick': _tickCount,
      'time': timeStr,
      'lastGoldFetch': _lastGoldFetchTime?.toIso8601String(),
    });

    _log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  }

  /// Perform gold price fetch with detailed logging
  Future<void> _performGoldPriceFetch(DateTime timestamp) async {
    final timeLabel = DateFormat('hh:mm a').format(timestamp);
    _log('🌕 [GOLD] Starting gold price fetch at $timeLabel...');

    try {
      // Initialize services in background isolate
      final notificationPlugin = FlutterLocalNotificationsPlugin();

      // Initialize local notifications
      const AndroidInitializationSettings androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initSettings =
          InitializationSettings(android: androidInit);
      await notificationPlugin.initialize(initSettings);

      // Create/ensure gold price channel exists
      final androidImpl = notificationPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        const AndroidNotificationChannel goldChannel = AndroidNotificationChannel(
          'gold_price_channel',
          'Gold Price Alerts',
          description: 'Scheduled notifications for gold price updates',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        );
        await androidImpl.createNotificationChannel(goldChannel);
      }

      // Fetch gold price
      final goldService = GoldPriceService();
      _log('🌕 [GOLD] Fetching from GoodReturns (primary) and BankBazaar (secondary)...');

      final result = await goldService.fetchCurrentGoldPrice();
      final newPrice = result['price'] as GoldPrice?;

      if (newPrice != null) {
        _log('💰 [GOLD] ✅ Price fetched successfully: ₹${newPrice.price}');
        _log('💰 [GOLD] Method: ${result['method']}');

        // Get previous price for comparison
        final storageService = StorageService();
        final prevPrice = await storageService.getLatestGoldPrice();
        double change = 0.0;
        if (prevPrice != null) {
          change = newPrice.price - prevPrice.price;
          _log('🔍 [GOLD] Previous: ₹${prevPrice.price} | Change: ₹$change');
        } else {
          _log('🔍 [GOLD] No previous price found (first fetch)');
        }

        // Save to DB
        final updatedPrice = GoldPrice(
          date: newPrice.date,
          timestamp: newPrice.timestamp,
          price: newPrice.price,
          priceChange: change,
        );
        await storageService.saveGoldPrice(updatedPrice);
        _log('💾 [GOLD] Price saved to database');

        // Build notification text
        String changeText = "";
        if (change != 0.0) {
          String sign = change > 0 ? "+" : "-";
          String emoji = change > 0 ? "📈" : "📉";
          changeText = " ($emoji $sign₹${change.abs().toStringAsFixed(0)})";
        } else {
          changeText = " (➖ No change)";
        }

        // Show notification
        await notificationPlugin.show(
          8000 + (_tickCount % 100), // Slightly different ID to avoid collapsing
          '💰 Gold Price Update ($timeLabel)',
          'Today: ₹${newPrice.price.toStringAsFixed(0)}$changeText',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'gold_price_channel',
              'Gold Price Alerts',
              channelDescription: 'Gold price updates',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
              icon: '@mipmap/ic_launcher',
            ),
          ),
          payload: 'gold_tab',
        );

        _lastGoldFetchTime = timestamp;
        _log('📬 [GOLD] ✅ NOTIFICATION SENT successfully');
        _log('📬 [GOLD] Title: Gold Price Update ($timeLabel)');
        _log('📬 [GOLD] Body: Today: ₹${newPrice.price.toStringAsFixed(0)}$changeText');
      } else {
        _log('❌ [GOLD] FETCH FAILED');
        _log('❌ [GOLD] Method: ${result['method']}');
        _log('❌ [GOLD] Debug: ${result['debug']}');

        // Show failure notification
        await notificationPlugin.show(
          8001,
          '⚠️ Gold Price Fetch Failed ($timeLabel)',
          'Could not fetch price. Method: ${result['method']}',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'gold_price_channel',
              'Gold Price Alerts',
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
              icon: '@mipmap/ic_launcher',
            ),
          ),
          payload: 'gold_tab',
        );
        _log('📬 [GOLD] ⚠️ FAILURE notification sent');
      }
    } catch (e, stackTrace) {
      _log('💥 [GOLD] FATAL ERROR during gold fetch: $e');
      _log('💥 [GOLD] Stack: ${stackTrace.toString().substring(0, stackTrace.toString().length.clamp(0, 200))}');
    }
  }

  /// Check if it's time for shift notification (10 PM daily)
  Future<void> _checkAndSendShiftNotification(DateTime timestamp) async {
    final hour = timestamp.hour;
    final minute = timestamp.minute;

    // Send shift notification if it's between 21:57 and 22:03 (to account for 3-min interval)
    // and we haven't sent one today
    if (hour == 22 || (hour == 21 && minute >= 57)) {
      final today = DateFormat('yyyy-MM-dd').format(timestamp);
      final lastSentDate = _lastShiftNotifyTime != null
          ? DateFormat('yyyy-MM-dd').format(_lastShiftNotifyTime!)
          : '';

      if (lastSentDate != today) {
        _log('📅 [SHIFT] Time for shift notification (${hour}:${minute.toString().padLeft(2, '0')})');

        try {
          final shiftService = ShiftService();
          await shiftService.showShiftNotification();
          _lastShiftNotifyTime = timestamp;
          _log('📅 [SHIFT] ✅ Shift notification sent');
        } catch (e) {
          _log('📅 [SHIFT] ❌ Error sending shift notification: $e');
        }
      } else {
        _log('📅 [SHIFT] Already sent today, skipping');
      }
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _log('🛑 ForegroundTask destroyed (isTimeout: $isTimeout) at $timestamp');
  }

  @override
  void onReceiveData(Object data) {
    _log('📨 Received data from main: $data');
  }

  @override
  void onNotificationButtonPressed(String id) {
    _log('🔘 Notification button pressed: $id');
  }

  @override
  void onNotificationPressed() {
    _log('📱 Notification pressed - launching app');
    FlutterForegroundTask.launchApp();
  }

  @override
  void onNotificationDismissed() {
    _log('🚫 Notification dismissed');
  }

  /// Helper to log with timestamp (works in background isolate)
  void _log(String message) {
    final timestamp = DateFormat('HH:mm:ss').format(DateTime.now());
    print('[$timestamp] [FG_TASK] $message');
    // Also use static log for LogService
    LogService.staticLog('[FG_TASK] $message');
  }
}
