import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../main.dart'; // To access navigatorKey
import '../screens/gold_screen.dart';
import '../screens/daily_reminders_screen.dart';
import '../screens/my_shifts_screen.dart';
import 'log_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  Future<void> init() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 1. Get Token
    messaging.getToken().then((token) {
      LogService.staticLog("FCM Token: $token");
    });

    // 2. Handle background notifications (When user taps notification while app is in background)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      LogService.staticLog("Notification clicked (from background): ${message.data['type']}");
      _handleNavigation(message);
    });

    // 3. Handle notification that launched the app from killed state
    RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      LogService.staticLog("Notification clicked (from killed): ${initialMessage.data['type']}");
      _handleNavigation(initialMessage);
    }

    // 4. Listen for foreground FCM messages (just logging for now)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      LogService.staticLog("Received foreground FCM: ${message.notification?.title}");
    });
  }

  void _handleNavigation(RemoteMessage message) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    final type = message.data['type'];

    switch (type) {
      case 'GOLD_PRICE':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const GoldScreen()),
        );
        break;
      case 'daily_reminder':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const DailyRemindersScreen()),
        );
        break;
      case 'shift_reminder':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const MyShiftsScreen()),
        );
        break;
      default:
        LogService.staticLog("Unknown notification type for navigation: $type");
    }
  }
}
