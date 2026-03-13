import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../services/storage_service.dart';
import '../services/shift_service.dart';
import '../services/notification_service.dart';
import '../services/log_service.dart';
import '../services/gold_scheduler_service.dart';
import '../services/foreground_task_service.dart';
import 'background_service.dart';

/// Service to reinitialize app state on startup
/// Ensures notifications are rescheduled and data is loaded
class AppInitService {
  static final AppInitService _instance = AppInitService._internal();
  factory AppInitService() => _instance;
  AppInitService._internal();

  /// Initialize app on startup
  /// This should be called in main() after other services
  Future<void> initialize() async {
    try {
      LogService.staticLog('🚀 Initializing app...');
      
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        LogService.staticLog('ℹ️ No user logged in, skipping notification reschedule');
        return;
      }
      
      // Reschedule task notifications
      await _rescheduleTaskNotifications();
      
      // Reschedule shift notifications if shifts exist
      await _rescheduleShiftNotifications();
      
      // Reschedule gold price alarms (BACKUP mechanism)
      await GoldSchedulerService().scheduleGoldPriceFetching();
      
      // Register background periodic task as resilience backup
      await BackgroundService().registerPeriodicTask();
      
      // Reschedule daily reminders if any exist
      await _rescheduleDailyReminders();
      
      // Ensure foreground service is running (PRIMARY mechanism)
      await _ensureForegroundServiceRunning();
      
      LogService.staticLog('✅ App initialization complete');
    } catch (e) {
      LogService.staticLog('❌ Error during app initialization: $e');
    }
  }

  /// Reschedule all tasks
  Future<void> _rescheduleTaskNotifications() async {
    try {
      final storage = StorageService();
      final tasks = await storage.getTasks();
      
      if (tasks.isNotEmpty) {
        final notificationService = NotificationService();
        for (final task in tasks) {
           await notificationService.scheduleTaskNotification(task);
        }
        LogService.staticLog('✅ ${tasks.length} task notifications rescheduled');
      }
    } catch (e) {
      LogService.staticLog('⚠️ Could not reschedule task notifications: $e');
    }
  }

  /// Reschedule shift notifications if shift data exists
  Future<void> _rescheduleShiftNotifications() async {
    try {
      final storage = StorageService();
      final metadata = await storage.getShiftMetadata();
      
      if (metadata != null) {
        final shiftService = ShiftService();
        await shiftService.scheduleDailyShiftNotification();
        LogService.staticLog('✅ Shift notifications rescheduled');
      }
    } catch (e) {
      LogService.staticLog('⚠️ Could not reschedule shift notifications: $e');
    }
  }

  /// Reschedule daily reminders
  Future<void> _rescheduleDailyReminders() async {
    try {
      final storage = StorageService();
      final reminders = await storage.getActiveDailyReminders();
      
      if (reminders.isNotEmpty) {
        final notificationService = NotificationService();
        for (final reminder in reminders) {
          await notificationService.scheduleDailyReminder(reminder);
        }
        LogService.staticLog('✅ ${reminders.length} daily reminders rescheduled');
      }
    } catch (e) {
      LogService.staticLog('⚠️ Could not reschedule daily reminders: $e');
    }
  }

  /// Ensure the foreground service is running
  Future<void> _ensureForegroundServiceRunning() async {
    try {
      final isRunning = await ForegroundTaskService().isRunning;
      if (!isRunning) {
        LogService.staticLog('⚠️ Foreground service was not running, starting...');
        ForegroundTaskService().init();
        final result = await ForegroundTaskService().startService();
        if (result is ServiceRequestSuccess) {
          LogService.staticLog('✅ Foreground service started');
        } else if (result is ServiceRequestFailure) {
          LogService.staticLog('❌ Foreground service failed: ${result.error}');
        }
      } else {
        LogService.staticLog('✅ Foreground service already running');
      }
    } catch (e) {
      LogService.staticLog('⚠️ Could not start foreground service: $e');
    }
  }
}
