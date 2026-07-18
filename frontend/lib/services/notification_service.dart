import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'log_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) async {
  WidgetsFlutterBinding.ensureInitialized();
  final payload = notificationResponse.payload;
  final actionId = notificationResponse.actionId;
  
  if (payload != null && actionId != null) {
    if (payload.startsWith("CALENDAR_REMINDER|")) {
      final parts = payload.split('|');
      final reminderId = parts[1];
      final uid = parts[2];
      
      try {
        await Firebase.initializeApp();
      } catch (_) {}
      
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('calendar_reminders')
          .doc(reminderId);
          
      if (actionId == 'action_yes') {
        final expireAt = DateTime.now().add(const Duration(days: 30));
        await docRef.update({
          'status': 'completed',
          'notifiedAt': FieldValue.serverTimestamp(),
          'expireAt': Timestamp.fromDate(expireAt),
        });
        LogService.staticLog("BG Handler: Marked reminder $reminderId as completed.");
      } else if (actionId == 'action_no') {
        final doc = await docRef.get();
        if (doc.exists) {
          final data = doc.data()!;
          final currentSnooze = data['currentSnoozeCount'] ?? 0;
          final maxSnooze = data['maxSnoozeCount'] ?? 3;
          final interval = data['snoozeIntervalMinutes'] ?? 15;
          
          if (currentSnooze < maxSnooze) {
            final nextTime = DateTime.now().add(Duration(minutes: interval));
            final dateStr = "${nextTime.year}-${nextTime.month.toString().padLeft(2, '0')}-${nextTime.day.toString().padLeft(2, '0')}";
            final timeStr = "${nextTime.hour.toString().padLeft(2, '0')}:${nextTime.minute.toString().padLeft(2, '0')}";
            
            await docRef.update({
              'date': dateStr,
              'time': timeStr,
              'status': 'pending',
              'currentSnoozeCount': currentSnooze + 1,
            });
            LogService.staticLog("BG Handler: Snoozed reminder $reminderId to $dateStr $timeStr (Snooze count: ${currentSnooze + 1}).");
          } else {
            final expireAt = DateTime.now().add(const Duration(days: 30));
            await docRef.update({
              'status': 'completed',
              'expireAt': Timestamp.fromDate(expireAt),
            });
            LogService.staticLog("BG Handler: Max snooze limit reached for $reminderId. Marked completed.");
          }
        }
      }
    } else if (payload.startsWith("DAILY_REMINDER|")) {
      final parts = payload.split('|');
      final reminderId = parts[1];
      final uid = parts[2];
      
      try {
        await Firebase.initializeApp();
      } catch (_) {}
      
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('daily_reminders')
          .doc(reminderId);
          
      if (actionId == 'action_done') {
        final now = DateTime.now();
        final todayDateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
        await docRef.update({
          'lastCompletedDate': todayDateStr,
          'currentSnoozeCount': 0,
        });
        LogService.staticLog("BG Handler: Marked daily reminder $reminderId as completed.");
      }
    }
  }
}

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
    if (!kIsWeb) {
      const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
      const DarwinInitializationSettings initializationSettingsDarwin = DarwinInitializationSettings();
      const InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsDarwin,
      );

      await _localNotifications.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) async {
          final payload = response.payload;
          final actionId = response.actionId;
          
          LogService.staticLog("Foreground Notification Tap: actionId=$actionId, payload=$payload");
          
          if (payload != null && actionId != null) {
            if (payload.startsWith("CALENDAR_REMINDER|")) {
              final parts = payload.split('|');
              final reminderId = parts[1];
              final uid = parts[2];
              
              final docRef = FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .collection('calendar_reminders')
                  .doc(reminderId);
                  
              if (actionId == 'action_yes') {
                final expireAt = DateTime.now().add(const Duration(days: 30));
                await docRef.update({
                  'status': 'completed',
                  'notifiedAt': FieldValue.serverTimestamp(),
                  'expireAt': Timestamp.fromDate(expireAt),
                });
                LogService.staticLog("FG Handler: Marked reminder $reminderId as completed.");
              } else if (actionId == 'action_no') {
                final doc = await docRef.get();
                if (doc.exists) {
                  final data = doc.data()!;
                  final currentSnooze = data['currentSnoozeCount'] ?? 0;
                  final maxSnooze = data['maxSnoozeCount'] ?? 3;
                  final interval = data['snoozeIntervalMinutes'] ?? 15;
                  
                  if (currentSnooze < maxSnooze) {
                    final nextTime = DateTime.now().add(Duration(minutes: interval));
                    final dateStr = "${nextTime.year}-${nextTime.month.toString().padLeft(2, '0')}-${nextTime.day.toString().padLeft(2, '0')}";
                    final timeStr = "${nextTime.hour.toString().padLeft(2, '0')}:${nextTime.minute.toString().padLeft(2, '0')}";
                    
                    await docRef.update({
                      'date': dateStr,
                      'time': timeStr,
                      'status': 'pending',
                      'currentSnoozeCount': currentSnooze + 1,
                    });
                    LogService.staticLog("FG Handler: Snoozed reminder $reminderId to $dateStr $timeStr.");
                  } else {
                    final expireAt = DateTime.now().add(const Duration(days: 30));
                    await docRef.update({
                      'status': 'completed',
                      'expireAt': Timestamp.fromDate(expireAt),
                    });
                    LogService.staticLog("FG Handler: Max snooze limit reached for $reminderId.");
                  }
                }
              }
            } else if (payload.startsWith("DAILY_REMINDER|")) {
              final parts = payload.split('|');
              final reminderId = parts[1];
              final uid = parts[2];
              
              final docRef = FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .collection('daily_reminders')
                  .doc(reminderId);
                  
              if (actionId == 'action_done') {
                final now = DateTime.now();
                final todayDateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
                await docRef.update({
                  'lastCompletedDate': todayDateStr,
                  'currentSnoozeCount': 0,
                });
                LogService.staticLog("FG Handler: Marked daily reminder $reminderId as completed.");
              }
            }
          }
          
          if (payload != null && payload != 'null') {
            _selectNotificationStream.add(payload);
          }
        },
        onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
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
    }

    // 4. Get Messaging Token and update Firestore
    // Note: VAPID key is strictly required on Web for push notifications to work.
    // Replace the placeholder below with your actual Web Push certificate key pair from Firebase Console -> Project Settings -> Cloud Messaging -> Web configuration.
    final String? vapidKey = kIsWeb ? 'YOUR_PUBLIC_VAPID_KEY_HERE' : null;
    messaging.getToken(vapidKey: vapidKey).then((token) async {
      LogService.staticLog("FCM Token: $token");
      if (token != null) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final query = await FirebaseFirestore.instance
              .collection('usernames')
              .where('uid', isEqualTo: user.uid)
              .limit(1)
              .get();
          if (query.docs.isNotEmpty) {
            await query.docs.first.reference.update({'fcmToken': token});
            LogService.staticLog("FCM Token updated in Firestore for ${user.uid}");
          }
        }
      }
    });

    // 5. Handle background notifications (When user taps notification while app is in background)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      final type = message.data['type'];
      LogService.staticLog("Notification clicked (from background): $type");
      if (type == 'CALENDAR_REMINDER') {
        final reminderId = message.data['reminderId'] ?? '';
        final user = FirebaseAuth.instance.currentUser;
        final uid = user?.uid ?? '';
        _selectNotificationStream.add("CALENDAR_REMINDER|$reminderId|$uid");
      } else if (type != null && type != 'null') {
        _selectNotificationStream.add(type);
      }
    });

    // 6. Handle notification that launched the app from killed state
    RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      final type = initialMessage.data['type'];
      LogService.staticLog("Notification clicked (from killed): $type");
      if (type == 'CALENDAR_REMINDER') {
        final reminderId = initialMessage.data['reminderId'] ?? '';
        final user = FirebaseAuth.instance.currentUser;
        final uid = user?.uid ?? '';
        Future.delayed(const Duration(seconds: 2), () {
          _selectNotificationStream.add("CALENDAR_REMINDER|$reminderId|$uid");
        });
      } else if (type != null && type != 'null') {
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
        String? payload = message.data['type'];
        
        if (payload == 'CALENDAR_REMINDER') {
          final reminderId = message.data['reminderId'] ?? '';
          final user = FirebaseAuth.instance.currentUser;
          final uid = user?.uid ?? '';
          payload = "CALENDAR_REMINDER|$reminderId|$uid";
        } else if (payload == 'daily_reminder') {
          final reminderId = message.data['reminderId'] ?? '';
          final user = FirebaseAuth.instance.currentUser;
          final uid = user?.uid ?? '';
          payload = "DAILY_REMINDER|$reminderId|$uid";
        }

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
              actions: (payload != null && payload.startsWith("DAILY_REMINDER|"))
                  ? <AndroidNotificationAction>[
                      const AndroidNotificationAction(
                        'action_done',
                        'Mark Done',
                        showsUserInterface: true,
                      ),
                    ]
                  : (payload != null && payload.startsWith("CALENDAR_REMINDER|"))
                      ? <AndroidNotificationAction>[
                          const AndroidNotificationAction(
                            'action_yes',
                            'Done',
                            showsUserInterface: true,
                          ),
                          const AndroidNotificationAction(
                            'action_no',
                            'Snooze',
                            showsUserInterface: true,
                          ),
                        ]
                      : null,
            ),
          ),
          payload: payload,
        );
      }
    });
  }
}
