import '../models/shift.dart';
import 'storage_service.dart';
import 'log_service.dart';

class ShiftService {
  static final ShiftService _instance = ShiftService._internal();
  factory ShiftService() => _instance;
  ShiftService._internal();

  final StorageService _storage = StorageService();

  Future<void> scheduleDailyShiftNotification({int hour = 22, int minute = 0}) async {
    // Cloud Functions will handle this now.
  }

  Future<void> showShiftNotification() async {
    // Cloud Functions will handle this now.
  }

  Future<void> cancelAllShiftNotifications() async {
    // Cloud Functions will handle this now.
  }
}
