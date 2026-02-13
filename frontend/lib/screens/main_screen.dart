import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'home_screen.dart';
import 'notes_screen.dart';
import 'daily_reminders_screen.dart';
import 'gold_screen.dart';
import 'checklists_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    // Simple shared preference check could go here
    // For now, default to light
  }

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
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
    // FIX: Removed invalid nested MaterialApp. 
    // This allows the root MaterialApp in main.dart to control navigation and theming properly.
    return Scaffold(
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
            icon: Icon(_themeMode == ThemeMode.light ? Icons.dark_mode : Icons.light_mode),
            onPressed: _toggleTheme,
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
                title: const Text('Settings'),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Settings coming soon!')),
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
                    applicationVersion: '1.1.0',
                    applicationIcon: const Icon(Icons.alarm_add, size: 48),
                    children: [
                      const Text('Your friendly daily reminder companion!'),
                      const SizedBox(height: 8),
                      const Text('Features:'),
                      const Text('• Calendar-based reminders'),
                      const Text('• Gold Price Tracker'),
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
    );
  }
}
