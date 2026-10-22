import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'log_service.dart';
import 'notification_service.dart';
import 'web_desktop_notifications/web_desktop_notifications.dart';

class AppPermissionService {
  static final AppPermissionService _instance = AppPermissionService._internal();
  factory AppPermissionService() => _instance;
  AppPermissionService._internal();

  static const MethodChannel _channel = MethodChannel('com.remindbuddy/permissions');

  /// Check if a specific permission is granted
  Future<bool> isPermissionGranted(String permissionName) async {
    if (kIsWeb) {
      if (permissionName == 'notification') {
        final perm = await WebDesktopNotificationService.getPermission();
        return perm == 'granted';
      }
      return false;
    }
    try {
      final bool? granted = await _channel.invokeMethod<bool>('checkPermission', {
        'permission': permissionName,
      });
      return granted ?? false;
    } catch (e) {
      LogService().error('Error checking permission: $permissionName', e);
      return false;
    }
  }

  /// Request a specific permission natively or via browser API
  Future<bool> requestPermission(String permissionName) async {
    if (kIsWeb) {
      if (permissionName == 'notification') {
        final res = await NotificationService().requestWebPushPermission();
        return res['success'] == true;
      }
      return false;
    }
    try {
      final bool? granted = await _channel.invokeMethod<bool>('requestPermission', {
        'permission': permissionName,
      });
      return granted ?? false;
    } catch (e) {
      LogService().error('Error requesting permission: $permissionName', e);
      return false;
    }
  }

  /// Open App System Settings
  Future<void> openAppSettings() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('openAppSettings');
    } catch (e) {
      LogService().error('Error opening app settings', e);
    }
  }

  /// Check and prompt for necessary permissions on launch/login
  /// Handles both native platforms (Android/iOS) and Web (iPhone Safari PWA / Chrome)
  Future<void> checkAndPromptInitialPermissions(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Web App & Safari PWA handling
      if (kIsWeb) {
        final String webStatus = await WebDesktopNotificationService.getPermission();
        final bool hasPromptedWeb = prefs.getBool('has_prompted_web_push_v3') ?? false;

        if (webStatus != 'granted' && !hasPromptedWeb) {
          if (!context.mounted) return;

          final bool isDenied = webStatus == 'denied';

          await showDialog(
            context: context,
            barrierDismissible: true,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  const Icon(Icons.notifications_active_rounded, color: Colors.blueAccent, size: 26),
                  const SizedBox(width: 10),
                  Text('Enable Notifications', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SmartBuddy delivers timely calendar alarms, shift rosters, and smart reminders directly to your device.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.phone_iphone_rounded, color: Colors.blueAccent, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'iPhone Users: For push notifications on iOS, tap Share (⬆️) ➔ "Add to Home Screen", then open SmartBuddy and allow notifications.',
                            style: TextStyle(fontSize: 11.5, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isDenied) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Notifications are currently blocked in your browser site settings.',
                              style: TextStyle(fontSize: 11.5, color: Colors.orange),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await prefs.setBool('has_prompted_web_push_v3', true);
                  },
                  child: const Text('Not Now'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await prefs.setBool('has_prompted_web_push_v3', true);
                    if (isDenied) {
                      if (context.mounted) {
                        showWebPermissionGuidanceDialog(context);
                      }
                    } else {
                      final res = await NotificationService().requestWebPushPermission();
                      if (context.mounted) {
                        if (res['success'] == true) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('🚀 Web Push notifications enabled!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        } else if (res['denied'] == true) {
                          showWebPermissionGuidanceDialog(context);
                        }
                      }
                    }
                  },
                  child: Text(isDenied ? 'How to Unblock' : 'Allow Notifications'),
                ),
              ],
            ),
          );
        }
        return;
      }

      // Native (Android / iOS)
      final bool hasPrompted = prefs.getBool('has_prompted_initial_permissions_v3') ?? false;
      final bool hasNotification = await isPermissionGranted('notification');
      final bool hasLocation = await isPermissionGranted('location');

      if ((!hasNotification || !hasLocation) && !hasPrompted) {
        if (!context.mounted) return;

        await showDialog(
          context: context,
          barrierDismissible: true,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.verified_user_rounded, color: Colors.blueAccent, size: 26),
                const SizedBox(width: 10),
                Text('Permissions Required', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'To provide timely reminders and real-time local updates, SmartBuddy requires the following permissions:',
                  style: TextStyle(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 14),
                _buildPermissionRow(
                  icon: Icons.notifications_active_rounded,
                  color: Colors.purpleAccent,
                  title: 'Notifications',
                  desc: 'Delivers calendar alarms, shift rosters, and smart expense alerts.',
                  isGranted: hasNotification,
                ),
                const SizedBox(height: 12),
                _buildPermissionRow(
                  icon: Icons.location_on_rounded,
                  color: Colors.teal,
                  title: 'Location',
                  desc: 'Detects city for accurate local weather and gold rates.',
                  isGranted: hasLocation,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await prefs.setBool('has_prompted_initial_permissions_v3', true);
                },
                child: const Text('Not Now'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await prefs.setBool('has_prompted_initial_permissions_v3', true);
                  if (!hasNotification) {
                    await requestPermission('notification');
                  }
                  if (!hasLocation) {
                    await requestPermission('location');
                  }
                },
                child: const Text('Grant Permissions', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      LogService().error('Error prompting initial permissions', e);
    }
  }

  /// Displays comprehensive step-by-step instructions to enable notifications
  /// for iPhone Safari PWA, Android Chrome, and Desktop browsers.
  Future<void> showWebPermissionGuidanceDialog(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.help_outline_rounded, color: Colors.blueAccent),
            SizedBox(width: 10),
            Text('Enable Notifications'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Follow the quick steps below for your device to receive calendar and workout alerts:',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 14),

              // iPhone Safari Guide
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.purple.withValues(alpha: 0.25)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.apple, color: Colors.purple, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'iPhone Safari (iOS 16.4+)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.purple),
                        ),
                      ],
                    ),
                    SizedBox(height: 6),
                    Text(
                      '1. Tap the Safari Share button (⬆️) at the bottom.\n'
                      '2. Scroll down and tap "Add to Home Screen".\n'
                      '3. Open the SmartBuddy icon from your Home Screen.\n'
                      '4. Go to iPhone Settings ➔ Notifications ➔ SmartBuddy and switch Allow Notifications to ON.',
                      style: TextStyle(fontSize: 12, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Android Chrome Guide
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.teal.withValues(alpha: 0.25)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.android, color: Colors.teal, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Android (Chrome / Samsung Internet)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal),
                        ),
                      ],
                    ),
                    SizedBox(height: 6),
                    Text(
                      '1. Tap the lock/tune icon (🔒) on the left of the address bar.\n'
                      '2. Tap "Permissions" or "Site Settings".\n'
                      '3. Set Notifications to "Allow".',
                      style: TextStyle(fontSize: 12, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Try Again Now'),
            onPressed: () async {
              Navigator.pop(ctx);
              final res = await NotificationService().requestWebPushPermission();
              if (context.mounted) {
                if (res['success'] == true) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('🚀 Web Push notifications enabled!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else if (res['denied'] == true) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Still blocked in browser settings. Please follow the steps above.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  /// Ensure Microphone permission for Ask Buddy (Voice Assistant)
  Future<bool> ensureMicrophonePermission(BuildContext context) async {
    final bool granted = await isPermissionGranted('microphone');
    if (granted) return true;

    if (!context.mounted) return false;

    final bool? proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.mic_rounded, color: Colors.redAccent, size: 24),
            const SizedBox(width: 8),
            Text('Microphone Access', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: const Text(
          'Ask Buddy Voice Assistant requires microphone access to listen to your voice commands and transcribe speech into tasks and questions.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Allow Microphone'),
          ),
        ],
      ),
    );

    if (proceed == true) {
      return await requestPermission('microphone');
    }
    return false;
  }

  /// Ensure SMS and Restricted Settings guidance for Smart Bank Tracker
  Future<bool> ensureSmsPermissionWithRestrictedGuide(BuildContext context) async {
    final bool granted = await isPermissionGranted('sms');
    if (granted) return true;

    if (!context.mounted) return false;

    final bool? proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.sms_rounded, color: Colors.blueAccent, size: 24),
            const SizedBox(width: 8),
            Text('SMS Permission Needed', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Smart Bank Tracker reads bank transaction SMS messages locally on your device to calculate your balance and cashflow. Your SMS data never leaves your device.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline_rounded, color: Colors.amber, size: 16),
                        SizedBox(width: 6),
                        Text('Android 13 / 14 Notice', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.amber)),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      'If Android shows "Restricted Setting":\n1. Tap "Open App Info" below.\n2. Tap the 3 dots (⋮) in the top-right corner.\n3. Tap "Allow restricted settings".\n4. Re-open SmartBuddy and grant SMS permission.',
                      style: TextStyle(fontSize: 11.5, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx, false);
              openAppSettings();
            },
            child: const Text('Open App Info'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Grant SMS Permission'),
          ),
        ],
      ),
    );

    if (proceed == true) {
      return await requestPermission('sms');
    }
    return false;
  }

  static Widget _buildPermissionRow({
    required IconData icon,
    required Color color,
    required String title,
    required String desc,
    required bool isGranted,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                  if (isGranted)
                    const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 16),
                ],
              ),
              const SizedBox(height: 2),
              Text(desc, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
      ],
    );
  }
}
