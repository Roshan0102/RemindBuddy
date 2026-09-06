import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'log_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home_widget_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  LogService.staticLog("FCM Background message received: ${message.data}");
  
  if (message.data['type'] == 'GOLD_PRICE') {
    final rateStr = message.data['rate22k'];
    final changeStr = message.data['changeToday'];
    final tsStr = message.data['timestamp'];

    final rate = double.tryParse(rateStr?.toString() ?? '') ?? 0.0;
    final change = double.tryParse(changeStr?.toString() ?? '') ?? 0.0;
    final updateTime = tsStr != null ? DateTime.tryParse(tsStr.toString()) : null;
    
    if (rate > 0) {
      await HomeWidgetService().updateGoldWidget(
        rate22k: rate,
        changeToday: change,
        updatedAt: updateTime,
      );
      LogService.staticLog("FCM BG: Successfully updated GoldWidget to rate $rate (change: $change)");
    }
  }
}

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
          final pairedDocId = data['pairedDocId'] as String?;
          final pairedUid = data['pairedUid'] as String?;
          
          if (currentSnooze + 1 < maxSnooze) {
            final nextTime = DateTime.now().add(Duration(minutes: interval));
            final dateStr = "${nextTime.year}-${nextTime.month.toString().padLeft(2, '0')}-${nextTime.day.toString().padLeft(2, '0')}";
            final timeStr = "${nextTime.hour.toString().padLeft(2, '0')}:${nextTime.minute.toString().padLeft(2, '0')}";
            
            final updates = {
              'date': dateStr,
              'time': timeStr,
              'status': 'pending',
              'currentSnoozeCount': currentSnooze + 1,
            };

            await docRef.update(updates);

            if (pairedDocId != null && pairedUid != null) {
              try {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(pairedUid)
                    .collection('calendar_reminders')
                    .doc(pairedDocId)
                    .update(updates);
              } catch (e) {
                debugPrint("Error updating paired snooze reminder: $e");
              }
            }
            LogService.staticLog("BG Handler: Snoozed reminder $reminderId to $dateStr $timeStr (Snooze count: ${currentSnooze + 1}).");
          } else {
            final expireAt = DateTime.now().add(const Duration(days: 30));
            final updates = {
              'status': 'completed',
              'expireAt': Timestamp.fromDate(expireAt),
            };
            await docRef.update(updates);
            if (pairedDocId != null && pairedUid != null) {
              try {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(pairedUid)
                    .collection('calendar_reminders')
                    .doc(pairedDocId)
                    .update(updates);
              } catch (_) {}
            }
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

  // Buffered payload for cold-start launches
  String? _pendingPayload;

  String? consumePendingPayload() {
    final payload = _pendingPayload;
    _pendingPayload = null;
    return payload;
  }

  void handleNotificationPayload(String payload) {
    if (payload.isEmpty || payload == 'null') return;
    _pendingPayload = payload;
    _selectNotificationStream.add(payload);
  }

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  Future<void> init() async {
    if (kIsWeb) {
      LogService.staticLog("Notifications disabled on Web platform (Mobile-only requirement).");
      return;
    }
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    
    // 1. Register Background FCM message handler
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (e) {
      LogService.staticLog("Error registering onBackgroundMessage: $e");
    }

    // 2. Request Permission
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 3. Setup Local Notifications (for Foreground support & Channels)
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
                  final pairedDocId = data['pairedDocId'] as String?;
                  final pairedUid = data['pairedUid'] as String?;
                  
                  if (currentSnooze + 1 < maxSnooze) {
                    final nextTime = DateTime.now().add(Duration(minutes: interval));
                    final dateStr = "${nextTime.year}-${nextTime.month.toString().padLeft(2, '0')}-${nextTime.day.toString().padLeft(2, '0')}";
                    final timeStr = "${nextTime.hour.toString().padLeft(2, '0')}:${nextTime.minute.toString().padLeft(2, '0')}";
                    
                    final updates = {
                      'date': dateStr,
                      'time': timeStr,
                      'status': 'pending',
                      'currentSnoozeCount': currentSnooze + 1,
                    };

                    await docRef.update(updates);

                    if (pairedDocId != null && pairedUid != null) {
                      try {
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(pairedUid)
                            .collection('calendar_reminders')
                            .doc(pairedDocId)
                            .update(updates);
                      } catch (e) {
                        debugPrint("Error updating paired snooze reminder: $e");
                      }
                    }
                    LogService.staticLog("FG Handler: Snoozed reminder $reminderId to $dateStr $timeStr.");
                  } else {
                    final expireAt = DateTime.now().add(const Duration(days: 30));
                    final updates = {
                      'status': 'completed',
                      'expireAt': Timestamp.fromDate(expireAt),
                    };
                    await docRef.update(updates);
                    if (pairedDocId != null && pairedUid != null) {
                      try {
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(pairedUid)
                            .collection('calendar_reminders')
                            .doc(pairedDocId)
                            .update(updates);
                      } catch (_) {}
                    }
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
          
          if (payload != null && payload.isNotEmpty && payload != 'null') {
            handleNotificationPayload(payload);
          }
        },
        onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      );

      // 3. Create Android Channels
      const List<AndroidNotificationChannel> channels = [
        AndroidNotificationChannel(
          'bill_reminder_channel',
          'Bill & Subscription Reminders',
          description: 'Notifications for upcoming and due bills/subscriptions',
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
          'gold_price_channel',
          'Gold Price Alerts',
          description: 'Notifications for gold price updates and AI forecasts',
          importance: Importance.max,
          playSound: true,
        ),
        AndroidNotificationChannel(
          'events_reminder_channel',
          'Tech Events Reminders',
          description: 'Notifications for interested tech events and meetups',
          importance: Importance.max,
          playSound: true,
        ),
        AndroidNotificationChannel(
          'walkin_reminder_channel',
          'Walk-In Drives Alerts',
          description: 'Notifications for walk-in job interview drives',
          importance: Importance.max,
          playSound: true,
        ),
        AndroidNotificationChannel(
          'job_assistant_channel',
          'AI Job Assistant Alerts',
          description: 'Notifications for auto-applied jobs and application status',
          importance: Importance.max,
          playSound: true,
        ),
        AndroidNotificationChannel(
          'collaboration_channel',
          'Collaboration Alerts',
          description: 'Notifications for shared tasks and team activities',
          importance: Importance.max,
          playSound: true,
        ),
        AndroidNotificationChannel(
          'astro_reminder_channel',
          'Astro Calendar Alerts',
          description: 'Notifications for lunar phases and astro events',
          importance: Importance.max,
          playSound: true,
        ),
        AndroidNotificationChannel(
          'finance_reminder_channel',
          'Finance & Bank Tracker Alerts',
          description: 'Notifications for daily untagged transactions and manual spend reminders',
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
    const String? vapidKey = kIsWeb ? 'YOUR_PUBLIC_VAPID_KEY_HERE' : null;
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
      final type = message.data['type'] ?? message.data['click_action'] ?? '';
      LogService.staticLog("Notification clicked (from background FCM): $type, data: ${message.data}");
      String? payload = type;
      if (type == 'CALENDAR_REMINDER') {
        final reminderId = message.data['reminderId'] ?? '';
        final user = FirebaseAuth.instance.currentUser;
        final uid = user?.uid ?? message.data['uid'] ?? '';
        payload = "CALENDAR_REMINDER|$reminderId|$uid";
      } else if (type == 'daily_reminder') {
        final reminderId = message.data['reminderId'] ?? '';
        final user = FirebaseAuth.instance.currentUser;
        final uid = user?.uid ?? message.data['uid'] ?? '';
        payload = "DAILY_REMINDER|$reminderId|$uid";
      }
      if (payload != null && payload.isNotEmpty && payload != 'null') {
        handleNotificationPayload(payload);
      }
    });

    // 6. Handle notification that launched the app from killed state
    // A. Check local notification launch details
    if (!kIsWeb) {
      try {
        final NotificationAppLaunchDetails? launchDetails =
            await _localNotifications.getNotificationAppLaunchDetails();
        if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
          final payload = launchDetails.notificationResponse?.payload;
          LogService.staticLog("Notification clicked (from killed local notification): $payload");
          if (payload != null && payload.isNotEmpty && payload != 'null') {
            _pendingPayload = payload;
          }
        }
      } catch (e) {
        LogService.staticLog("Error checking getNotificationAppLaunchDetails: $e");
      }
    }

    // B. Check FCM initial message
    try {
      RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        final type = initialMessage.data['type'] ?? initialMessage.data['click_action'] ?? '';
        LogService.staticLog("Notification clicked (from killed FCM): $type, data: ${initialMessage.data}");
        String? payload = type;
        if (type == 'CALENDAR_REMINDER') {
          final reminderId = initialMessage.data['reminderId'] ?? '';
          final user = FirebaseAuth.instance.currentUser;
          final uid = user?.uid ?? initialMessage.data['uid'] ?? '';
          payload = "CALENDAR_REMINDER|$reminderId|$uid";
        } else if (type == 'daily_reminder') {
          final reminderId = initialMessage.data['reminderId'] ?? '';
          final user = FirebaseAuth.instance.currentUser;
          final uid = user?.uid ?? initialMessage.data['uid'] ?? '';
          payload = "DAILY_REMINDER|$reminderId|$uid";
        }
        if (payload != null && payload.isNotEmpty && payload != 'null') {
          _pendingPayload = payload;
        }
      }
    } catch (e) {
      LogService.staticLog("Error checking FCM getInitialMessage: $e");
    }

    // 7. Listen for foreground FCM messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      LogService.staticLog("Received foreground FCM: ${message.notification?.title}");
      
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      if (message.data['type'] == 'GOLD_PRICE') {
        final rateStr = message.data['rate22k'];
        final changeStr = message.data['changeToday'];
        final tsStr = message.data['timestamp'];

        final rate = double.tryParse(rateStr?.toString() ?? '') ?? 0.0;
        final change = double.tryParse(changeStr?.toString() ?? '') ?? 0.0;
        final updateTime = tsStr != null ? DateTime.tryParse(tsStr.toString()) : null;

        if (rate > 0) {
          HomeWidgetService().updateGoldWidget(
            rate22k: rate,
            changeToday: change,
            updatedAt: updateTime,
          );
        }
      }

      if (notification != null && android != null) {
        String? payload = message.data['type'] ?? message.data['click_action'];
        
        bool isSnoozeEnabled = false;
        if (payload == 'CALENDAR_REMINDER') {
          final reminderId = message.data['reminderId'] ?? '';
          final user = FirebaseAuth.instance.currentUser;
          final uid = user?.uid ?? message.data['uid'] ?? '';
          isSnoozeEnabled = message.data['snoozeEnabled'] == 'true';
          payload = "CALENDAR_REMINDER|$reminderId|$uid";
        } else if (payload == 'daily_reminder') {
          final reminderId = message.data['reminderId'] ?? '';
          final user = FirebaseAuth.instance.currentUser;
          final uid = user?.uid ?? message.data['uid'] ?? '';
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
                  : (payload != null && payload.startsWith("CALENDAR_REMINDER|") && isSnoozeEnabled)
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

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String channelId = 'calendar_reminder_channel',
    String channelName = 'Calendar Reminders',
    String? payload,
  }) async {
    if (kIsWeb) return;
    await _localNotifications.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: payload,
    );
  }
}
