class WebDesktopNotifications {
  static bool get isSupported => false;
  static Future<String> getPermission() async => 'denied';
  static Future<String> requestPermission() async => 'denied';
  static void showNotification({
    required String title,
    required String body,
    String? tag,
    String? payload,
  }) {}
}
