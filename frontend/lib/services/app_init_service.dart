import '../services/storage_service.dart';
import '../services/shift_service.dart';
import '../services/notification_service.dart';
import '../services/log_service.dart';

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
      
      // Reschedule shift notifications if shifts exist
      await _rescheduleShiftNotifications();
      
      // Reschedule daily reminders if any exist
      await _rescheduleDailyReminders();
      
      LogService.staticLog('✅ App initialization complete');
    } catch (e) {
      LogService.staticLog('❌ Error during app initialization: $e');
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
}
