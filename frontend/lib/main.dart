import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'screens/main_screen.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  try {
    await NotificationService().init();
    await BackgroundService().init();
    await BackgroundService().registerPeriodicTask();
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
