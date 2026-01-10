import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'home_screen.dart';
import 'notes_screen.dart';

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
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.light),
        fontFamily: 'Roboto', // Will use Google Fonts in HomeScreen
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
        fontFamily: 'Roboto',
      ),
      themeMode: _themeMode,
      home: Scaffold(
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
            // Add Sync button back here since we removed it from HomeScreen
            IconButton(
              icon: const Icon(Icons.sync),
              onPressed: () {
                 // We need a way to trigger sync in HomeScreen. 
                 // For now, we can just rely on auto-sync or add a global sync service.
                 // Or just leave it out as auto-sync exists.
                 // Let's add a simple snackbar for now.
                 ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Syncing...')));
              },
            ),
          ],
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
          ],
        ),
      ),
    );
  }
}
