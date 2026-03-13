import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'screens/main_screen.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';
import 'services/gold_scheduler_service.dart';
import 'services/foreground_task_service.dart';
import 'services/app_init_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // Set the background messaging handler early on, as a top-level function.
  FirebaseMessaging.onBackgroundMessage(NotificationService.firebaseMessagingBackgroundHandler);

  // Initialize port for communication between ForegroundTask and UI
  FlutterForegroundTask.initCommunicationPort();

  await initializeDateFormatting();
  try {
    await NotificationService().init();
    
    // Initialize Workmanager (kept as backup)
    await BackgroundService().init();
    
    // Initialize old alarm-based scheduler (kept as backup)
    await GoldSchedulerService().init();
    await GoldSchedulerService().scheduleGoldPriceFetching();
    print('✅ Gold price scheduler initialized (backup alarms)');
    
    // *** NEW: Initialize and start Foreground Task Service ***
    // This is the PRIMARY mechanism for reliable background notifications
    ForegroundTaskService().init();
    final result = await ForegroundTaskService().startService();
    if (result is ServiceRequestSuccess) {
      print('✅ Foreground Task Service: STARTED');
    } else if (result is ServiceRequestFailure) {
      print('❌ Foreground Task Service FAILED: ${result.error}');
    }
    
    // Initialize app state (reschedule notifications, etc.)
    await AppInitService().initialize();
  } catch (e) {
    print('Error initializing services: $e');
  }
  
  runApp(const RemindBuddyApp());
}

class RemindBuddyApp extends StatelessWidget {
  const RemindBuddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RemindBuddy',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}
