import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'home_screen.dart';
import 'notes_screen.dart';
import 'checklists_screen.dart';
import 'gold_price_screen.dart';
import 'my_shifts_screen.dart';
import 'settings_screen.dart';
import 'voice_listening_overlay.dart';
import '../services/storage_service.dart';
import '../services/notification_service.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final PageController _pageController = PageController();
  final StorageService _storageService = StorageService();
  final NotificationService _notificationService = NotificationService();
  
  List<String> _enabledModules = ['gold']; // Default to gold only

  @override
  void initState() {
    super.initState();
    _loadUserPreferences();
  }

  Future<void> _loadUserPreferences() async {
    final prefs = await _storageService.getUserPreferences();
    if (mounted) {
      setState(() {
        _enabledModules = List<String>.from(prefs['enabledModules'] ?? ['gold']);
      });
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      const HomeScreen(),
      const NotesScreen(),
      const ChecklistsScreen(),
      const GoldPriceScreen(),
      const MyShiftsScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.note), label: 'Notes'),
          BottomNavigationBarItem(icon: Icon(Icons.checklist), label: 'Checklist'),
          BottomNavigationBarItem(icon: Icon(Icons.trending_up), label: 'Gold'),
          BottomNavigationBarItem(icon: Icon(Icons.work), label: 'Shifts'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
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
    );
  }
}
