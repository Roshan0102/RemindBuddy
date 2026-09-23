// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import '../notification_service.dart';

class WebDesktopNotifications {
  /// Checks if HTML5 Desktop Notifications are supported by current browser
  static bool get isSupported {
    try {
      return html.Notification.supported;
    } catch (_) {
      return false;
    }
  }

  /// Returns current browser permission: 'granted', 'denied', or 'default'
  static Future<String> getPermission() async {
    if (!isSupported) return 'denied';
    try {
      return html.Notification.permission ?? 'default';
    } catch (_) {
      return 'denied';
    }
  }

  /// Prompts browser for notification permission
  static Future<String> requestPermission() async {
    if (!isSupported) return 'denied';
    try {
      final res = await html.Notification.requestPermission();
      return res;
    } catch (e) {
      debugPrint('Error requesting notification permission: $e');
      return 'denied';
    }
  }

  /// Displays an OS native desktop notification in the browser
  static void showNotification({
    required String title,
    required String body,
    String? tag,
    String? payload,
  }) {
    if (!isSupported) return;
    try {
      final perm = html.Notification.permission;
      if (perm != 'granted') {
        debugPrint('Cannot show desktop notification, permission is $perm');
        return;
      }

      final notification = html.Notification(
        title,
        body: body,
        icon: '/icons/Icon-192.png',
        tag: tag ?? 'remindbuddy_${DateTime.now().millisecondsSinceEpoch}',
      );

      notification.onClick.listen((_) {
        try {
          (html.window as dynamic).focus();
        } catch (_) {}

        if (payload != null && payload.isNotEmpty) {
          try {
            NotificationService().handleNotificationPayload(payload);
          } catch (e) {
            debugPrint('Error handling desktop notification click: $e');
          }
        }
        notification.close();
      });
    } catch (e) {
      debugPrint('Error showing HTML5 desktop notification: $e');
    }
  }

  static bool _swListenerInitialized = false;

  /// Listens for messages dispatched from the service worker on notification clicks
  static void initServiceWorkerListener() {
    if (!isSupported || _swListenerInitialized) return;
    _swListenerInitialized = true;
    try {
      html.window.navigator.serviceWorker?.addEventListener('message', (html.Event event) {
        if (event is html.MessageEvent) {
          final data = event.data;
          if (data is Map) {
            final action = data['action'];
            final feature = data['feature'] ?? data['type'];
            if (action == 'NAVIGATE_FEATURE' && feature != null && feature.toString().isNotEmpty) {
              debugPrint('[RemindBuddy Web] Received NAVIGATE_FEATURE from Service Worker: $feature');
              NotificationService().handleNotificationPayload(feature.toString());
            }
          }
        }
      });
    } catch (e) {
      debugPrint('Error setting up SW message listener: $e');
    }
  }
}
