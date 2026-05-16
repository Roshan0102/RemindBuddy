import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';
import 'notes_screen.dart';
import 'daily_reminders_screen.dart';
import 'gold_screen.dart';
import 'checklists_screen.dart';
import 'my_shifts_screen.dart';
import 'auth_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/log_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import 'settings_screen.dart';
import 'voice_listening_overlay.dart';
import 'package:permission_handler/permission_handler.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  bool _isDarkMode = false;
  List<String> _enabledModules = ['gold'];
  bool _isLoading = true;

  StreamSubscription? _notificationSubscription;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _setupNotificationListener();
  }

  Future<void> _loadInitialData() async {
    await _loadTheme();
    await _loadPreferences();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await StorageService().getUserPreferences();
    if (mounted) {
      setState(() {
        _enabledModules = List<String>.from(prefs['enabledModules'] ?? _enabledModules);
        // Ensure index is valid
        if (_selectedIndex >= _enabledModules.length) {
          _selectedIndex = 0;
        }
      });
    }
  }

  void _setupNotificationListener() {
    _notificationSubscription = NotificationService().selectNotificationStream.listen((type) {
      LogService.staticLog("MainScreen received notification event: $type");
      if (!mounted) return;

      setState(() {
        switch (type) {
          case 'GOLD_PRICE':
            _selectedIndex = 0; // Gold Tab
            break;
          case 'CALENDAR_REMINDER':
            _selectedIndex = 1; // Reminders Tab
            break;
          case 'shift_reminder':
            _selectedIndex = 3; // Shifts Tab
            break;
          case 'daily_reminder':
            // This is a separate screen in the drawer
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const DailyRemindersScreen()),
            );
            break;
        }
      });
    });
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    super.dispose();
  }



  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    });
  }

  Future<void> _toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
    await prefs.setBool('isDarkMode', _isDarkMode);
  }

  final Map<String, Map<String, dynamic>> _moduleRegistry = {
    'gold': {
      'screen': const GoldScreen(),
      'destination': const NavigationDestination(
        icon: Icon(Icons.monetization_on_outlined, color: Colors.amber),
        selectedIcon: Icon(Icons.monetization_on, color: Colors.amber),
        label: 'Gold',
      ),
    },
    'reminders': {
      'screen': const HomeScreen(),
      'destination': const NavigationDestination(
        icon: Icon(Icons.calendar_today_outlined, color: Colors.indigo),
        selectedIcon: Icon(Icons.calendar_today, color: Colors.indigo),
        label: 'Reminders',
      ),
    },
    'notes': {
      'screen': const NotesScreen(),
      'destination': const NavigationDestination(
        icon: Icon(Icons.note_alt_outlined, color: Colors.teal),
        selectedIcon: Icon(Icons.note_alt, color: Colors.teal),
        label: 'Notes',
      ),
    },
    'shifts': {
      'screen': const MyShiftsScreen(),
      'destination': const NavigationDestination(
        icon: Icon(Icons.work_history_outlined, color: Colors.orange),
        selectedIcon: Icon(Icons.work_history, color: Colors.orange),
        label: 'Shifts',
      ),
    },
    'checklist': {
      'screen': const ChecklistsScreen(),
      'destination': const NavigationDestination(
        icon: Icon(Icons.playlist_add_check_outlined, color: Colors.blue),
        selectedIcon: Icon(Icons.playlist_add_check, color: Colors.blue),
        label: 'Checklist',
      ),
    },
  };

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // FIX: Wrap with Theme to apply dark/light mode
    return Theme(
      data: _isDarkMode 
        ? ThemeData.dark(useMaterial3: true).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.dark,
            ),
          )
        : ThemeData.light(useMaterial3: true).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.light,
            ),
          ),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'RemindBuddy',
            style: GoogleFonts.pacifico( // Creative Font
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: Icon(_isDarkMode ? Icons.light_mode : Icons.dark_mode),
              onPressed: _toggleTheme,
              tooltip: _isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            ),
          ],
        ),
      drawer: Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.primaryContainer,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Icon(Icons.alarm_add, size: 48, color: Colors.white),
                    const SizedBox(height: 8),
                    Text(
                      'RemindBuddy',
                      style: GoogleFonts.pacifico(
                        fontSize: 24,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Your Daily Companion',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add_check_outlined, color: Colors.blue),
                title: const Text('Checklist'),
                subtitle: const Text('Checklists for travel/office'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ChecklistsScreen()),
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.calendar_today, color: Colors.indigo),
                title: const Text('Reminders'),
                selected: _selectedIndex == 1,
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _selectedIndex = 1);
                },
              ),
              ListTile(
                leading: const Icon(Icons.note_alt, color: Colors.teal),
                title: const Text('Notes'),
                selected: _selectedIndex == 2,
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _selectedIndex = 2);
                },
              ),
              ListTile(
                leading: const Icon(Icons.monetization_on, color: Colors.amber),
                title: const Text('Gold Rates'),
                selected: _selectedIndex == 0,
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _selectedIndex = 0);
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.alarm_on, color: Colors.blue),
                title: const Text('Daily Reminders'),
                subtitle: const Text('Recurring reminders'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const DailyRemindersScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.work_history, color: Colors.purple),
                title: const Text('My Shifts'),
                subtitle: const Text('Work schedule & reminders'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const MyShiftsScreen()),
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.settings_suggest, color: Colors.blueGrey),
                title: const Text('Customize App'),
                subtitle: const Text('Hide/Show features'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SettingsScreen()),
                  ).then((_) => _loadPreferences());
                },
              ),
              const Divider(),
              // Login / Profile Feature
              ListTile(
                leading: Icon(
                  FirebaseAuth.instance.currentUser != null ? Icons.account_circle : Icons.login, 
                  color: Colors.teal
                ),
                title: Text(FirebaseAuth.instance.currentUser != null ? 'My Profile' : 'Login'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AuthScreen()),
                  ).then((_) {
                    setState(() {});
                    _loadPreferences(); // Reload prefs in case user logged in/out
                  });
                },
              ),

              const Divider(),
              ListTile(
                leading: const Icon(Icons.bug_report, color: Colors.orange),
                title: const Text('System Logs & Debug'),
                subtitle: const Text('Check notification status'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const LogScreen()),
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('About'),
                onTap: () {
                  Navigator.pop(context);
                  showAboutDialog(
                    context: context,
                    applicationName: 'RemindBuddy',
                    applicationVersion: '1.2.8',
                    applicationIcon: const Icon(Icons.alarm_add, size: 48),
                    children: [
                      const Text('Your friendly daily reminder companion!'),
                      const SizedBox(height: 8),
                      const Text('Features:'),
                      const Text('• Calendar-based reminders'),
                      const Text('• Gold Price Tracker'),
                      const Text('• My Shifts - Work schedule manager'),
                      const Text('• Checklists for everything'),
                      const Text('• Secure notes with PIN lock'),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(
              index: _selectedIndex,
              children: _enabledModules
                  .where((id) => _moduleRegistry.containsKey(id))
                  .map((id) => _moduleRegistry[id]!['screen'] as Widget)
                  .toList(),
            ),
        bottomNavigationBar: _isLoading 
          ? null 
          : NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onItemTapped,
              destinations: _enabledModules
                  .where((id) => _moduleRegistry.containsKey(id))
                  .map((id) => _moduleRegistry[id]!['destination'] as NavigationDestination)
                  .toList(),
            ),
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            final status = await Permission.microphone.request();
            if (status.isGranted) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const VoiceListeningOverlay()),
              );
            }
          },
          backgroundColor: Colors.blueAccent,
          child: const Icon(Icons.mic, color: Colors.white),
        ),
      ), // Close Scaffold
    ); // Close Theme
  }
}
