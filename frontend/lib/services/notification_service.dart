import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../main.dart'; // To access navigatorKey
import '../screens/gold_screen.dart';
import '../screens/daily_reminders_screen.dart';
import '../screens/my_shifts_screen.dart';
import 'log_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  Future<void> init() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    
    // 1. Request Permission
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 2. Setup Local Notifications (for Foreground support & Channels)
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsDarwin = DarwinInitializationSettings();
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // This handles taps on local notifications (foreground ones)
        if (response.payload != null) {
          LogService.staticLog("Local Notification clicked: ${response.payload}");
          _handleNavigationByType(response.payload!);
        }
      },
    );

    // 3. Create Android Channels (Critical for reliability)
    const List<AndroidNotificationChannel> channels = [
      AndroidNotificationChannel(
        'gold_price_channel',
        'Gold Price Alerts',
        description: 'Notifications for gold price updates',
        importance: Importance.max,
        playSound: true,
      ),
      AndroidNotificationChannel(
        'daily_reminder_channel',
        'Daily Reminders',
        description: 'Notifications for your personal daily reminders',
        importance: Importance.max,
        playSound: true,
      ),
      AndroidNotificationChannel(
        'shift_reminder_channel',
        'Shift Reminders',
        description: 'Notifications for your work shift schedule',
        importance: Importance.max,
        playSound: true,
      ),
    ];

    final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      for (var channel in channels) {
        await androidPlugin.createNotificationChannel(channel);
      }
    }

    // 4. Get Messaging Token
    messaging.getToken().then((token) {
      LogService.staticLog("FCM Token: $token");
    });

    // 5. Handle background notifications (When user taps notification while app is in background)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      LogService.staticLog("Notification clicked (from background): ${message.data['type']}");
      _handleNavigation(message);
    });

    // 6. Handle notification that launched the app from killed state
    RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      LogService.staticLog("Notification clicked (from killed): ${initialMessage.data['type']}");
      _handleNavigation(initialMessage);
    }

    // 7. Listen for foreground FCM messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      LogService.staticLog("Received foreground FCM: ${message.notification?.title}");
      
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      if (notification != null && android != null) {
        _localNotifications.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              android.channelId ?? 'gold_price_channel',
              'Default Notifications',
              importance: Importance.max,
              priority: Priority.high,
              icon: android.smallIcon,
            ),
          ),
          payload: message.data['type'],
        );
      }
    });
  }

  void _handleNavigation(RemoteMessage message) {
    _handleNavigationByType(message.data['type']);
  }

  void _handleNavigationByType(String? type) {
    final context = navigatorKey.currentContext;
    if (context == null || type == null) return;

    LogService.staticLog("Navigating to screen for type: $type");

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
