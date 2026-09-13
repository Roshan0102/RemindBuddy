import 'web_desktop_notifications_stub.dart'
    if (dart.library.html) 'web_desktop_notifications_web.dart' as impl;

class WebDesktopNotificationService {
  static bool get isSupported => impl.WebDesktopNotifications.isSupported;

  static Future<String> getPermission() => impl.WebDesktopNotifications.getPermission();

  static Future<String> requestPermission() => impl.WebDesktopNotifications.requestPermission();

  static void showNotification({
    required String title,
    required String body,
    String? tag,
    String? payload,
  }) {
    impl.WebDesktopNotifications.showNotification(
      title: title,
      body: body,
      tag: tag,
      payload: payload,
    );
  }
}
