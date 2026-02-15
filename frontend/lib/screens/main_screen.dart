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

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  bool _isDarkMode = false;

  @override
  void initState() {
    super.initState();
    _loadTheme();
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

  final List<Widget> _screens = [
    const HomeScreen(),
    const NotesScreen(),
    const GoldScreen(),
  ];

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
                leading: const Icon(Icons.backpack_outlined, color: Colors.green),
                title: const Text('My Belongings (Packing)'),
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
                leading: const Icon(Icons.calendar_today),
                title: const Text('Reminders'),
                selected: _selectedIndex == 0,
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _selectedIndex = 0);
                },
              ),
              ListTile(
                leading: const Icon(Icons.note_alt),
                title: const Text('Notes'),
                selected: _selectedIndex == 1,
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _selectedIndex = 1);
                },
              ),
              ListTile(
                leading: const Icon(Icons.monetization_on),
                title: const Text('Gold Rates'),
                selected: _selectedIndex == 2,
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _selectedIndex = 2);
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
              /*
              ListTile(
                leading: const Icon(Icons.bug_report, color: Colors.grey),
                title: const Text('Gold Price Test (Debug)'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const GoldPriceTestScreen()),
                  );
                },
              ),
              */
              const Divider(),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Settings (Login/Sync)'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AuthScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('About'),
                onTap: () {
                  Navigator.pop(context);
                  showAboutDialog(
                    context: context,
                    applicationName: 'RemindBuddy',
                    applicationVersion: '1.0.33',
                    applicationIcon: const Icon(Icons.alarm_add, size: 48),
                    children: [
                      const Text('Your friendly daily reminder companion!'),
                      const SizedBox(height: 8),
                      const Text('Features:'),
                      const Text('• Calendar-based reminders'),
                      const Text('• Gold Price Tracker'),
                      const Text('• My Shifts - Work schedule manager'),
                      const Text('• My Belongings Checklists'),
                      const Text('• Secure notes with PIN lock'),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        body: IndexedStack(
          index: _selectedIndex,
          children: _screens,
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _onItemTapped,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.calendar_today_outlined),
              selectedIcon: Icon(Icons.calendar_today),
              label: 'Reminders',
            ),
            NavigationDestination(
              icon: Icon(Icons.note_alt_outlined),
              selectedIcon: Icon(Icons.note_alt),
              label: 'Notes',
            ),
             NavigationDestination(
              icon: Icon(Icons.monetization_on_outlined),
              selectedIcon: Icon(Icons.monetization_on),
              label: 'Gold',
            ),
          ],
        ),
      ), // Close Scaffold
    ); // Close Theme
  }
}
