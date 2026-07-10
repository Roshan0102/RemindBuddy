import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'screens/main_screen.dart';
import 'screens/auth_screen.dart';
import 'services/notification_service.dart';
import 'firebase_options.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.light);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  await initializeDateFormatting();
  
  // Load saved theme preference
  try {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('isDarkMode') ?? false;
    themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
  } catch (e) {
    print('Error loading theme preference: $e');
  }
  
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
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return ValueListenableBuilder<ThemeMode>(
            valueListenable: themeNotifier,
            builder: (_, ThemeMode currentMode, __) {
              return MaterialApp(
                title: 'RemindBuddy',
                debugShowCheckedModeBanner: false,
                themeMode: currentMode,
                theme: ThemeData(
                  brightness: Brightness.light,
                  useMaterial3: true,
                ),
                darkTheme: ThemeData(
                  brightness: Brightness.dark,
                  useMaterial3: true,
                ),
                home: const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                ),
              );
            },
          );
        }
        
        final bool isLoggedIn = snapshot.hasData && snapshot.data != null;
        
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: themeNotifier,
          builder: (_, ThemeMode currentMode, __) {
            return MaterialApp(
              title: 'RemindBuddy',
              debugShowCheckedModeBanner: false,
              navigatorKey: navigatorKey,
              themeMode: currentMode,
              theme: ThemeData(
                primarySwatch: Colors.blue,
                useMaterial3: true,
                brightness: Brightness.light,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.blue,
                  brightness: Brightness.light,
                ),
              ),
              darkTheme: ThemeData(
                primarySwatch: Colors.blue,
                useMaterial3: true,
                brightness: Brightness.dark,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.blue,
                  brightness: Brightness.dark,
                ),
              ),
              home: isLoggedIn ? const MainScreen() : const AuthScreen(),
            );
          },
        );
      },
    );
  }
}

