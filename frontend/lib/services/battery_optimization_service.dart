import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BatteryOptimizationService {
  static const platform = MethodChannel('com.remindbuddy/battery');

  /// Check if battery optimization is enabled for the app
  static Future<bool> isBatteryOptimizationEnabled() async {
    try {
      final bool result = await platform.invokeMethod('isBatteryOptimizationEnabled');
      return result;
    } on PlatformException catch (e) {
      print("Failed to check battery optimization: '${e.message}'.");
      return true;
    }
  }

  /// Check if exact alarm permission is granted (Android 12+)
  static Future<bool> isExactAlarmPermissionGranted() async {
    try {
      final bool result = await platform.invokeMethod('isExactAlarmPermissionGranted');
      return result;
    } on PlatformException catch (e) {
      print("Failed to check exact alarm: '${e.message}'.");
      return true;
    }
  }

  /// Request to disable battery optimization
  static Future<void> requestDisableBatteryOptimization() async {
    try {
      await platform.invokeMethod('requestDisableBatteryOptimization');
    } on PlatformException catch (e) {
      print("Failed to request battery optimization: '${e.message}'.");
    }
  }

  /// Request exact alarm permission
  static Future<void> requestExactAlarmPermission() async {
    try {
      await platform.invokeMethod('requestExactAlarmPermission');
    } on PlatformException catch (e) {
      print("Failed to request alarm permission: '${e.message}'.");
    }
  }

  /// Open Autostart settings directly (Vivo/iQOO support)
  static Future<void> openAutostartSettings() async {
    try {
      await platform.invokeMethod('openAutostartSettings');
    } on PlatformException catch (e) {
      print("Failed to open autostart: '${e.message}'.");
    }
  }

  /// Open Notification settings directly
  static Future<void> openNotificationSettings() async {
    try {
      await platform.invokeMethod('openNotificationSettings');
    } on PlatformException catch (e) {
      print("Failed to open notifications: '${e.message}'.");
    }
  }

  /// Show a dialog explaining why these are needed for iQOO/Vivo users
  static Future<void> showOptimizationPanel(BuildContext context) async {
    final isOptimized = await isBatteryOptimizationEnabled();
    final isAlarmGranted = await isExactAlarmPermissionGranted();
    
    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '⚙️ Background & Notifications',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Essential for reliable Gold & Shift updates on iQOO/Vivo.',
                style: TextStyle(color: Colors.grey),
              ),
              const Divider(height: 32),
              
              _buildSettingItem(
                context,
                title: 'Alarms & Reminders',
                status: isAlarmGranted,
                description: 'Required for fixed-time updates (11 AM / 7 PM).',
                icon: Icons.access_alarm,
                onPressed: () => requestExactAlarmPermission(),
              ),
              
              _buildSettingItem(
                context,
                title: 'Battery Optimization',
                status: !isOptimized,
                description: 'Set to "Unrestricted" or "High Background Usage".',
                icon: Icons.battery_charging_full,
                onPressed: () => requestDisableBatteryOptimization(),
              ),

              _buildSettingItem(
                context,
                title: 'Autostart',
                status: null, // We can't easily check this from code
                description: 'Allow RemindBuddy to wake up on its own.',
                icon: Icons.shutter_speed,
                onPressed: () => openAutostartSettings(),
              ),

              _buildSettingItem(
                context,
                title: 'Notification Settings',
                status: null,
                description: 'Ensure "Important Notifications" are allowed.',
                icon: Icons.notifications_active,
                onPressed: () => openNotificationSettings(),
              ),
              
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('I Have Configured These'),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  static Widget _buildSettingItem(
    BuildContext context, {
    required String title,
    required bool? status,
    required String description,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    Color statusColor = status == true ? Colors.green : (status == false ? Colors.orange : Colors.blue);
    String statusText = status == true ? 'OK' : (status == false ? 'NOT SET' : 'CONFIGURE');

    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: InkWell(
        onTap: onPressed,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: statusColor),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(description, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                statusText,
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
