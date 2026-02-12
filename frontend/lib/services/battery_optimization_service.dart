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
      return true; // Assume it's enabled if we can't check
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

  /// Show a dialog explaining why battery optimization should be disabled
  static Future<void> showBatteryOptimizationDialog(BuildContext context) async {
    final isOptimized = await isBatteryOptimizationEnabled();
    
    if (!isOptimized) {
      // Already disabled, no need to show dialog
      return;
    }

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.battery_alert, color: Colors.orange),
              SizedBox(width: 8),
              Text('Battery Optimization'),
            ],
          ),
          content: const SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'For reliable daily reminders, RemindBuddy needs to be excluded from battery optimization.',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 12),
                Text('Why is this needed?'),
                SizedBox(height: 4),
                Text(
                  '• Android may kill apps in the background to save battery\n'
                  '• This can prevent your daily reminders from firing\n'
                  '• Disabling optimization ensures reminders work reliably',
                  style: TextStyle(fontSize: 14),
                ),
                SizedBox(height: 12),
                Text(
                  'RemindBuddy uses minimal battery and only runs when needed for reminders.',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Later'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                requestDisableBatteryOptimization();
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }
}
