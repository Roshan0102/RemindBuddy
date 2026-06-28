import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'screens/main_screen.dart';
import 'screens/auth_screen.dart';
import 'services/notification_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  await initializeDateFormatting();
  
  try {
    await NotificationService().init();
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
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasData && snapshot.data != null) {
            return const MainScreen();
          }
          return const AuthScreen();
        },
      ),
    );
  }
}
