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
import 'web_desktop_notifications/web_desktop_notifications.dart';
import 'alarm_audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
          
      if (actionId == 'action_alarm_dismiss' || actionId == 'action_yes') {
        try {
          await AlarmAudioService().stopAlarm();
        } catch (_) {}
        final expireAt = DateTime.now().add(const Duration(days: 30));
        await docRef.update({
          'status': 'completed',
          'notifiedAt': FieldValue.serverTimestamp(),
          'expireAt': Timestamp.fromDate(expireAt),
        });
        LogService.staticLog("BG Handler: Marked reminder $reminderId as completed.");
      } else if (actionId == 'action_alarm_snooze') {
        try {
          await AlarmAudioService().stopAlarm();
        } catch (_) {}
        final nextTime = DateTime.now().add(const Duration(minutes: 10));
        final dateStr = "${nextTime.year}-${nextTime.month.toString().padLeft(2, '0')}-${nextTime.day.toString().padLeft(2, '0')}";
        final timeStr = "${nextTime.hour.toString().padLeft(2, '0')}:${nextTime.minute.toString().padLeft(2, '0')}";
        await docRef.update({
          'date': dateStr,
          'time': timeStr,
          'status': 'pending',
          'currentSnoozeCount': FieldValue.increment(1),
        });
        LogService.staticLog("BG Handler: Snoozed alarm reminder $reminderId to $dateStr $timeStr.");
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

  DateTime _webSessionStartTime = DateTime.now();
  StreamSubscription? _webNotificationSubscription;
  StreamSubscription? _webAuthSubscription;

  void _initWebNotifications() {
    if (!kIsWeb) return;
    _webSessionStartTime = DateTime.now();
    _webAuthSubscription?.cancel();

    _webAuthSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      _webNotificationSubscription?.cancel();
      if (user == null) return;

      LogService.staticLog("Web desktop notifications listener initialized for user ${user.uid}");
      _webNotificationSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('notifications')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(_webSessionStartTime))
          .snapshots()
          .listen((snapshot) async {
        for (var change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final data = change.doc.data();
            if (data == null) continue;

            final title = data['title']?.toString() ?? 'RemindBuddy Alert';
            final body = data['body']?.toString() ?? '';
            final type = data['type']?.toString() ?? '';

            try {
              final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
              final notifPrefs = Map<String, dynamic>.from(userDoc.data()?['notificationPreferences'] ?? {});
              final bool desktopEnabled = notifPrefs['desktop_notifications'] ?? true;
              if (!desktopEnabled) continue;

              bool featureEnabled = true;
              if (type == 'SHIFT_REMINDER' && notifPrefs['shifts'] == false) featureEnabled = false;
              if (type == 'JOB_ASSISTANT' && notifPrefs['job_assistant'] == false) featureEnabled = false;
              if (type == 'JOB_ASSISTANT_REPLY' && notifPrefs['job_assistant'] == false) featureEnabled = false;
              if (type == 'CALENDAR_REMINDER' && notifPrefs['calendar_reminders'] == false) featureEnabled = false;
              if (type == 'DAILY_REMINDER' && notifPrefs['daily_reminders'] == false) featureEnabled = false;
              if (type == 'BILL_REMINDER' && notifPrefs['finance_bills'] == false) featureEnabled = false;
              if (type == 'TECH_EVENTS' && notifPrefs['events'] == false) featureEnabled = false;
              if (type == 'WALKIN_DRIVES' && notifPrefs['walkin'] == false) featureEnabled = false;
              if (type == 'GOLD_PRICE' && notifPrefs['gold_rates'] == false) featureEnabled = false;
              if (type == 'GOLD_CHIT_ADVICE' && notifPrefs['gold_advice'] == false) featureEnabled = false;
              if (type == 'ASTRO_CALENDAR' && notifPrefs['astro_calendar'] == false) featureEnabled = false;

              if (featureEnabled) {
                WebDesktopNotificationService.showNotification(
                  title: title,
                  body: body,
                  payload: type,
                  tag: 'notif_${change.doc.id}',
                );
              }
            } catch (e) {
              debugPrint("Error handling web notification doc: $e");
            }
          }
        }
      });
    });
  }

  Future<void> init() async {
    if (kIsWeb) {
      LogService.staticLog("Initializing Web Desktop Notifications.");
      _initWebNotifications();
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
                  
              if (actionId == 'action_alarm_dismiss' || actionId == 'action_yes') {
                try {
                  await AlarmAudioService().stopAlarm();
                } catch (_) {}
                final expireAt = DateTime.now().add(const Duration(days: 30));
                await docRef.update({
                  'status': 'completed',
                  'notifiedAt': FieldValue.serverTimestamp(),
                  'expireAt': Timestamp.fromDate(expireAt),
                });
                LogService.staticLog("FG Handler: Marked reminder $reminderId as completed.");
              } else if (actionId == 'action_alarm_snooze') {
                try {
                  await AlarmAudioService().stopAlarm();
                } catch (_) {}
                final nextTime = DateTime.now().add(const Duration(minutes: 10));
                final dateStr = "${nextTime.year}-${nextTime.month.toString().padLeft(2, '0')}-${nextTime.day.toString().padLeft(2, '0')}";
                final timeStr = "${nextTime.hour.toString().padLeft(2, '0')}:${nextTime.minute.toString().padLeft(2, '0')}";
                await docRef.update({
                  'date': dateStr,
                  'time': timeStr,
                  'status': 'pending',
                  'currentSnoozeCount': FieldValue.increment(1),
                });
                LogService.staticLog("FG Handler: Snoozed alarm reminder $reminderId to $dateStr $timeStr.");
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
        AndroidNotificationChannel(
          'alarm_reminder_channel_alarm_digital',
          'Digital Alarm Reminders',
          description: 'High priority digital alarm notifications with continuous ringing',
          importance: Importance.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('alarm_digital'),
          audioAttributesUsage: AudioAttributesUsage.alarm,
        ),
        AndroidNotificationChannel(
          'alarm_reminder_channel_alarm_siren',
          'Siren Alarm Reminders',
          description: 'High priority siren alarm notifications with continuous ringing',
          importance: Importance.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('alarm_siren'),
          audioAttributesUsage: AudioAttributesUsage.alarm,
        ),
        AndroidNotificationChannel(
          'alarm_reminder_channel_alarm_chime',
          'Chime Alarm Reminders',
          description: 'High priority chime alarm notifications with continuous ringing',
          importance: Importance.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('alarm_chime'),
          audioAttributesUsage: AudioAttributesUsage.alarm,
        ),
        AndroidNotificationChannel(
          'alarm_reminder_channel_custom',
          'Custom Alarm Reminders',
          description: 'High priority custom alarm notifications with continuous ringing',
          importance: Importance.max,
          playSound: false,
          audioAttributesUsage: AudioAttributesUsage.alarm,
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
    if (kIsWeb) {
      getWebPushVapidKey().then((vapidKey) async {
        if (vapidKey != null && vapidKey.isNotEmpty) {
          try {
            final token = await messaging.getToken(vapidKey: vapidKey);
            if (token != null) {
              await saveTokenToFirestore(token);
              LogService.staticLog("Web FCM Token refreshed: ${token.substring(0, 10)}...");
            }
          } catch (e) {
            LogService.staticLog("Web FCM Token startup check note: $e");
          }
        }
      });
    } else {
      messaging.getToken().then((token) async {
        LogService.staticLog("FCM Token: $token");
        if (token != null) {
          await saveTokenToFirestore(token);
        }
      });
    }

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

        final isAlarmMode = message.data['isAlarmMode'] == 'true';
        final alarmSound = message.data['alarmSound'] ?? 'digital';
        final String? customAudioPath = message.data['customAudioPath'];

        if (isAlarmMode) {
          final reminderId = message.data['reminderId'];
          showAlarmNotification(
            id: notification.hashCode,
            title: notification.title ?? 'Reminder Alarm',
            body: notification.body ?? '',
            payload: payload ?? '',
            sound: alarmSound,
          );

          if (alarmSound == 'custom' && (customAudioPath == null || customAudioPath.isEmpty)) {
            final uid = FirebaseAuth.instance.currentUser?.uid ?? message.data['uid'];
            if (uid != null && reminderId != null) {
              FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .collection('calendar_reminders')
                  .doc(reminderId)
                  .get()
                  .then((doc) {
                final path = doc.data()?['customAudioPath'] as String?;
                AlarmAudioService().startAlarm(
                  sound: alarmSound,
                  customPath: path,
                  reminderId: reminderId,
                );
              }).catchError((_) {
                AlarmAudioService().startAlarm(sound: alarmSound, reminderId: reminderId);
              });
            } else {
              AlarmAudioService().startAlarm(sound: alarmSound, reminderId: reminderId);
            }
          } else {
            AlarmAudioService().startAlarm(
              sound: alarmSound,
              customPath: customAudioPath,
              reminderId: reminderId,
            );
          }
        } else {
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
      }
    });
  }

  Future<void> cancelNotification(int id) async {
    try {
      await _localNotifications.cancel(id);
    } catch (_) {}
  }

  Future<void> showAlarmNotification({
    required int id,
    required String title,
    required String body,
    required String payload,
    String sound = 'digital',
  }) async {
    if (kIsWeb) {
      WebDesktopNotificationService.showNotification(
        title: title,
        body: body,
        payload: payload,
      );
      return;
    }

    final bool isCustom = sound == 'custom';
    String rawSound = 'alarm_digital';
    if (sound == 'siren') rawSound = 'alarm_siren';
    if (sound == 'chime') rawSound = 'alarm_chime';

    final String channelId = isCustom ? 'alarm_reminder_channel_custom' : 'alarm_reminder_channel_$rawSound';

    final androidDetails = AndroidNotificationDetails(
      channelId,
      isCustom ? 'Custom Alarm Reminders' : 'Continuous Alarm Reminders ($sound)',
      channelDescription: 'High priority continuous ringing alarms',
      importance: Importance.max,
      priority: Priority.max,
      icon: '@mipmap/ic_launcher',
      sound: isCustom ? null : RawResourceAndroidNotificationSound(rawSound),
      playSound: !isCustom,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      additionalFlags: isCustom ? null : Int32List.fromList([4]), // FLAG_INSISTENT = 4
      actions: const <AndroidNotificationAction>[
        AndroidNotificationAction(
          'action_alarm_dismiss',
          'Dismiss',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          'action_alarm_snooze',
          'Snooze 10m',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );

    await _localNotifications.show(
      id,
      title,
      body,
      NotificationDetails(android: androidDetails),
      payload: payload,
    );
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String channelId = 'calendar_reminder_channel',
    String channelName = 'Calendar Reminders',
    String? payload,
  }) async {
    if (kIsWeb) {
      WebDesktopNotificationService.showNotification(
        title: title,
        body: body,
        payload: payload,
      );
      return;
    }
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

  static String? _cachedVapidKey;

  /// Fetches the public Web Push VAPID key dynamically from Firestore (system_config/web_push)
  /// or local SharedPreferences cache.
  static Future<String?> getWebPushVapidKey() async {
    if (!kIsWeb) return null;
    if (_cachedVapidKey != null && _cachedVapidKey!.isNotEmpty) {
      return _cachedVapidKey;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final localKey = prefs.getString('web_push_vapid_key');
      if (localKey != null && localKey.trim().isNotEmpty) {
        _cachedVapidKey = localKey.trim();
        return _cachedVapidKey;
      }
    } catch (_) {}

    try {
      final doc = await FirebaseFirestore.instance.collection('system_config').doc('web_push').get();
      if (doc.exists && doc.data() != null) {
        final remoteKey = doc.data()!['vapidKey']?.toString().trim();
        if (remoteKey != null && remoteKey.isNotEmpty) {
          _cachedVapidKey = remoteKey;
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('web_push_vapid_key', remoteKey);
          } catch (_) {}
          return _cachedVapidKey;
        }
      }
    } catch (e) {
      LogService.staticLog("Error fetching VAPID key from Firestore: $e");
    }
    return null;
  }

  /// Sets or overrides the VAPID key locally and in Firestore
  static Future<void> setWebPushVapidKey(String key) async {
    final cleanKey = key.trim();
    if (cleanKey.isEmpty) return;
    _cachedVapidKey = cleanKey;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('web_push_vapid_key', cleanKey);
    } catch (_) {}
    try {
      await FirebaseFirestore.instance.collection('system_config').doc('web_push').set({
        'vapidKey': cleanKey,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Saves the FCM token to both `users/{uid}` and `usernames/{username}` in Firestore
  Future<void> saveTokenToFirestore(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      // 1. Update user document
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fcmToken': token,
        'webFcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        'webPushEnabled': true,
      }, SetOptions(merge: true));

      // 2. Also update username record for backwards compatibility
      final query = await FirebaseFirestore.instance
          .collection('usernames')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        await query.docs.first.reference.update({'fcmToken': token});
      }
      LogService.staticLog("FCM Token saved in Firestore for ${user.uid}: ${token.substring(0, token.length > 10 ? 10 : token.length)}...");
    } catch (e) {
      LogService.staticLog("Error saving FCM token to Firestore: $e");
    }
  }

  /// Checks if web push is currently enabled for the user
  Future<bool> isWebPushActive() async {
    if (!kIsWeb) return false;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && doc.data() != null) {
        return doc.data()!['webPushEnabled'] == true;
      }
    } catch (_) {}
    return false;
  }

  /// Explicitly requests Web Push permission with a user gesture, fetches the VAPID key,
  /// retrieves the FCM token, and saves it to Firestore.
  Future<Map<String, dynamic>> requestWebPushPermission({String? customVapidKey}) async {
    if (!kIsWeb) {
      return {'success': false, 'message': 'Web Push is only applicable on web browsers.'};
    }

    try {
      if (customVapidKey != null && customVapidKey.trim().isNotEmpty) {
        await setWebPushVapidKey(customVapidKey);
      }

      // 1. Check & fetch VAPID key
      final vapidKey = await getWebPushVapidKey();
      if (vapidKey == null || vapidKey.isEmpty) {
        return {
          'success': false,
          'needsVapidKey': true,
          'message': 'Web Push VAPID key is not configured yet in Firestore (system_config/web_push).'
        };
      }

      // 2. Prompt for browser permission (User gesture)
      final NotificationSettings settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        // 3. Retrieve token using the fetched VAPID key
        final token = await FirebaseMessaging.instance.getToken(vapidKey: vapidKey);
        if (token != null && token.isNotEmpty) {
          await saveTokenToFirestore(token);
          return {
            'success': true,
            'token': token,
            'message': 'Web Push notifications successfully enabled on this device!'
          };
        } else {
          return {
            'success': false,
            'message': 'Failed to retrieve FCM Web Push token. Please verify your VAPID key in Firebase Console.'
          };
        }
      } else if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return {
          'success': false,
          'denied': true,
          'message': 'Notification permission was denied in your browser settings. Please allow notifications in site settings.'
        };
      } else {
        return {
          'success': false,
          'message': 'Notification permission was not granted.'
        };
      }
    } catch (e) {
      LogService.staticLog("Exception in requestWebPushPermission: $e");
      return {'success': false, 'error': e.toString(), 'message': 'Error: $e'};
    }
  }

  /// Disables Web Push notifications for the current session/device
  Future<void> disableWebPush() async {
    if (!kIsWeb) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'webPushEnabled': false,
          'notificationPreferences': {
            'desktop_notifications': false,
          }
        }, SetOptions(merge: true));
      }
      try {
        await FirebaseMessaging.instance.deleteToken();
      } catch (_) {}
      LogService.staticLog("Web Push disabled for current device");
    } catch (e) {
      LogService.staticLog("Error disabling Web Push: $e");
    }
  }
}
