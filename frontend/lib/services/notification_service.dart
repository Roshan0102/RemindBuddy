
import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'log_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  
  // Hub for notification click events
  final StreamController<String> _selectNotificationStream = StreamController<String>.broadcast();
  Stream<String> get selectNotificationStream => _selectNotificationStream.stream;

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
        if (response.payload != null && response.payload != 'null') {
          LogService.staticLog("Local Notification clicked: ${response.payload}");
          _selectNotificationStream.add(response.payload!);
        }
      },
    );

    // 3. Create Android Channels
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
      AndroidNotificationChannel(
        'calendar_reminder_channel',
        'Calendar Reminders',
        description: 'Notifications for tasks scheduled on specific dates',
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
      final type = message.data['type'];
      LogService.staticLog("Notification clicked (from background): $type");
      if (type != null && type != 'null') _selectNotificationStream.add(type);
    });

    // 6. Handle notification that launched the app from killed state
    RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      final type = initialMessage.data['type'];
      LogService.staticLog("Notification clicked (from killed): $type");
      if (type != null && type != 'null') {
        // Delay slightly to allow MainScreen to mount and listen
        Future.delayed(const Duration(seconds: 2), () {
          _selectNotificationStream.add(type);
        });
      }
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
}
