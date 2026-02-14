import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'screens/main_screen.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';
import 'services/gold_scheduler_service.dart';
import 'services/app_init_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  try {
    await NotificationService().init();
    
    // Initialize old background service (for other tasks if any)
    await BackgroundService().init();
    // Note: We're NOT registering the old periodic task anymore
    // await BackgroundService().registerPeriodicTask();
    
    // Initialize and schedule the new gold price fetcher
    await GoldSchedulerService().init();
    await GoldSchedulerService().scheduleGoldPriceFetching();
    print('✅ Gold price scheduler initialized');
    
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
