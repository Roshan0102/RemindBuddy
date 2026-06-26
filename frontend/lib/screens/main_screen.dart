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
import 'vault_tab_wrapper.dart';
import 'admin_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  bool _isDarkMode = false;
  List<String> _enabledModules = ['gold'];
  List<String> _userSelectedBottomModules = [];
  bool _isLoading = true;

  bool get _isVaultEnabled => _enabledModules.contains('vault');

  StreamSubscription? _notificationSubscription;
  StreamSubscription? _authSubscription;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _setupNotificationListener();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      _loadPreferences();
    });
  }

  Future<void> _loadInitialData() async {
    await _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final localPrefs = await SharedPreferences.getInstance();
    final isDark = localPrefs.getBool('isDarkMode') ?? false;
    final cachedBottom = localPrefs.getStringList('user_bottom_modules') ?? [];
    final cachedModulesStr = localPrefs.getStringList('cached_enabled_modules');

    if (mounted) {
      setState(() {
        _isDarkMode = isDark;
        if (cachedModulesStr != null) {
          _enabledModules = cachedModulesStr;
        }
        _userSelectedBottomModules = cachedBottom;
        _isLoading = false;
      });
    }

    try {
      final prefs = await StorageService().getUserPreferences();
      final firestoreModules = List<String>.from(prefs['enabledModules'] ?? ['gold']);
      await localPrefs.setStringList('cached_enabled_modules', firestoreModules);
      if (mounted) {
        setState(() {
          _enabledModules = firestoreModules;
        });
      }
    } catch (e) {
      print("Error loading user preferences in background: $e");
    }
  }

  void _setupNotificationListener() {
    _notificationSubscription = NotificationService().selectNotificationStream.listen((type) {
      LogService.staticLog("MainScreen received notification event: $type");
      if (!mounted) return;

      switch (type) {
        case 'GOLD_PRICE':
          _selectTabOrPush('gold');
          break;
        case 'CALENDAR_REMINDER':
          _selectTabOrPush('reminders');
          break;
        case 'shift_reminder':
          _selectTabOrPush('shifts');
          break;
        case 'daily_reminder':
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const DailyRemindersScreen()),
          );
          break;
      }
    });
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
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
      'name': 'Gold Rates',
      'destination': const NavigationDestination(
        icon: Icon(Icons.monetization_on_outlined, color: Colors.amber),
        selectedIcon: Icon(Icons.monetization_on, color: Colors.amber),
        label: 'Gold',
      ),
    },
    'reminders': {
      'screen': const HomeScreen(),
      'name': 'Reminders',
      'destination': const NavigationDestination(
        icon: Icon(Icons.calendar_today_outlined, color: Colors.indigo),
        selectedIcon: Icon(Icons.calendar_today, color: Colors.indigo),
        label: 'Reminders',
      ),
    },
    'notes': {
      'screen': const NotesScreen(),
      'name': 'Notes',
      'destination': const NavigationDestination(
        icon: Icon(Icons.note_alt_outlined, color: Colors.teal),
        selectedIcon: Icon(Icons.note_alt, color: Colors.teal),
        label: 'Notes',
      ),
    },
    'shifts': {
      'screen': const MyShiftsScreen(),
      'name': 'My Shifts',
      'destination': const NavigationDestination(
        icon: Icon(Icons.work_history_outlined, color: Colors.orange),
        selectedIcon: Icon(Icons.work_history, color: Colors.orange),
        label: 'Shifts',
      ),
    },
    'checklist': {
      'screen': const ChecklistsScreen(),
      'name': 'Checklist',
      'destination': const NavigationDestination(
        icon: Icon(Icons.playlist_add_check_outlined, color: Colors.blue),
        selectedIcon: Icon(Icons.playlist_add_check, color: Colors.blue),
        label: 'Checklist',
      ),
    },
    'vault': {
      'screen': const VaultTabWrapper(),
      'name': 'Secure Vault',
      'destination': const NavigationDestination(
        icon: Icon(Icons.shield_outlined, color: Colors.blueAccent),
        selectedIcon: Icon(Icons.shield, color: Colors.blueAccent),
        label: 'Vault',
      ),
    },
  };

  List<String> get _bottomBarModules {
    final adminEnabled = _enabledModules
        .where((id) => _moduleRegistry.containsKey(id) && (id != 'vault' || _isVaultEnabled))
        .toList();

    final activeUserSelected = _userSelectedBottomModules
        .where((id) => adminEnabled.contains(id))
        .toList();

    if (activeUserSelected.length == 4) {
      return activeUserSelected;
    }

    final result = <String>[];
    result.addAll(activeUserSelected);

    for (var id in adminEnabled) {
      if (result.length >= 4) break;
      if (!result.contains(id)) {
        result.add(id);
      }
    }

    return result;
  }

  bool _isModuleSelected(String id) {
    if (_selectedIndex < _bottomBarModules.length) {
      return _bottomBarModules[_selectedIndex] == id;
    }
    return false;
  }

  void _selectTabOrPush(String id) {
    final idx = _bottomBarModules.indexOf(id);
    if (idx != -1) {
      setState(() => _selectedIndex = idx);
    } else {
      final screen = _moduleRegistry[id]?['screen'] as Widget?;
      if (screen != null) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => screen),
        );
      }
    }
  }

  void _showCustomizeBottomBarDialog() async {
    final adminEnabled = _enabledModules.where((id) => _moduleRegistry.containsKey(id) && (id != 'vault' || _isVaultEnabled)).toList();
    List<String> tempSelected = List<String>.from(_bottomBarModules);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Customize Bottom Bar'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select exactly 4 features to show in the bottom navigation bar:'),
                  const SizedBox(height: 12),
                  ...adminEnabled.map((id) {
                    final isChecked = tempSelected.contains(id);
                    final label = _moduleRegistry[id]?['name'] ?? id.toUpperCase();
                    return CheckboxListTile(
                      title: Text(label),
                      value: isChecked,
                      activeColor: Theme.of(context).colorScheme.primary,
                      onChanged: (val) {
                        setDialogState(() {
                          if (val == true) {
                            if (tempSelected.length >= 4) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('You can only select up to 4 features.')),
                              );
                              return;
                            }
                            tempSelected.add(id);
                          } else {
                            if (tempSelected.length <= 1) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('You must select at least 1 feature.')),
                              );
                              return;
                            }
                            tempSelected.remove(id);
                          }
                        });
                      },
                    );
                  }),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: tempSelected.isEmpty
                      ? null
                      : () async {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setStringList('user_bottom_modules', tempSelected);
                          setState(() {
                            _userSelectedBottomModules = tempSelected;
                            _selectedIndex = 0;
                          });
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Bottom bar updated successfully!')),
                            );
                          }
                        },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAppMenuBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final menuItems = [
          {
            'id': 'reminders',
            'name': 'Reminders',
            'icon': Icons.calendar_today,
            'color': Colors.indigo,
            'action': () => _selectTabOrPush('reminders'),
          },
          {
            'id': 'gold',
            'name': 'Gold Rates',
            'icon': Icons.monetization_on,
            'color': Colors.amber,
            'action': () => _selectTabOrPush('gold'),
          },
          {
            'id': 'notes',
            'name': 'Notes',
            'icon': Icons.note_alt,
            'color': Colors.teal,
            'action': () => _selectTabOrPush('notes'),
          },
          {
            'id': 'checklist',
            'name': 'Checklist',
            'icon': Icons.playlist_add_check_outlined,
            'color': Colors.blue,
            'action': () => _selectTabOrPush('checklist'),
          },
          {
            'id': 'shifts',
            'name': 'My Shifts',
            'icon': Icons.work_history,
            'color': Colors.orange,
            'action': () => _selectTabOrPush('shifts'),
          },
          if (_isVaultEnabled)
            {
              'id': 'vault',
              'name': 'Secure Vault',
              'icon': Icons.shield,
              'color': Colors.blueAccent,
              'action': () => _selectTabOrPush('vault'),
            },
          {
            'id': 'daily_reminders',
            'name': 'Daily Reminders',
            'icon': Icons.alarm_on,
            'color': Colors.blue,
            'action': () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DailyRemindersScreen()),
              );
            },
          },
          {
            'id': 'customize',
            'name': 'Customize Bar',
            'icon': Icons.dashboard_customize,
            'color': Colors.purple,
            'action': () => _showCustomizeBottomBarDialog(),
          },
          {
            'id': 'admin',
            'name': 'Admin Console',
            'icon': Icons.admin_panel_settings,
            'color': Colors.blueGrey,
            'action': () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AdminScreen()),
              ).then((_) {
                _loadPreferences();
              });
            },
          },
        ];

        return Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'App Menu',
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.95,
                ),
                itemCount: menuItems.length,
                itemBuilder: (context, index) {
                  final item = menuItems[index];
                  return InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      (item['action'] as VoidCallback)();
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: (item['color'] as Color).withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: (item['color'] as Color).withOpacity(0.15),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            item['icon'] as IconData,
                            color: item['color'] as Color,
                            size: 28,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item['name'] as String,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

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
                selected: _isModuleSelected('checklist'),
                onTap: () {
                  Navigator.pop(context);
                  _selectTabOrPush('checklist');
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.calendar_today, color: Colors.indigo),
                title: const Text('Reminders'),
                selected: _isModuleSelected('reminders'),
                onTap: () {
                  Navigator.pop(context);
                  _selectTabOrPush('reminders');
                },
              ),
              ListTile(
                leading: const Icon(Icons.note_alt, color: Colors.teal),
                title: const Text('Notes'),
                selected: _isModuleSelected('notes'),
                onTap: () {
                  Navigator.pop(context);
                  _selectTabOrPush('notes');
                },
              ),
              ListTile(
                leading: const Icon(Icons.monetization_on, color: Colors.amber),
                title: const Text('Gold Rates'),
                selected: _isModuleSelected('gold'),
                onTap: () {
                  Navigator.pop(context);
                  _selectTabOrPush('gold');
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
                selected: _isModuleSelected('shifts'),
                onTap: () {
                  Navigator.pop(context);
                  _selectTabOrPush('shifts');
                },
              ),
              if (_isVaultEnabled) ...[
                ListTile(
                  leading: const Icon(Icons.shield, color: Colors.blueAccent),
                  title: const Text('Secure Vault'),
                  subtitle: const Text('Encrypt and save documents'),
                  selected: _isModuleSelected('vault'),
                  onTap: () {
                    Navigator.pop(context);
                    _selectTabOrPush('vault');
                  },
                ),
                const Divider(),
              ],

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
                leading: const Icon(Icons.admin_panel_settings, color: Colors.blueGrey),
                title: const Text('Admin Console'),
                subtitle: const Text('Configure features & permissions'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AdminScreen()),
                  ).then((_) {
                    _loadPreferences();
                  });
                },
              ),

              const Divider(),
              ListTile(
                leading: const Icon(Icons.dashboard_customize, color: Colors.teal),
                title: const Text('Customize Bottom Bar'),
                subtitle: const Text('Select your 4 primary features'),
                onTap: () {
                  Navigator.pop(context);
                  _showCustomizeBottomBarDialog();
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
              index: _selectedIndex < _bottomBarModules.length ? _selectedIndex : 0,
              children: _bottomBarModules
                  .map((id) => _moduleRegistry[id]!['screen'] as Widget)
                  .toList(),
            ),
        bottomNavigationBar: _isLoading 
          ? null 
          : NavigationBar(
              selectedIndex: _bottomBarModules.length == 4
                  ? (_selectedIndex < 2 ? _selectedIndex : _selectedIndex + 1)
                  : _selectedIndex,
              onDestinationSelected: (int index) {
                if (_bottomBarModules.length == 4) {
                  if (index == 2) {
                    _showAppMenuBottomSheet();
                  } else {
                    int targetIndex = index < 2 ? index : index - 1;
                    _onItemTapped(targetIndex);
                  }
                } else {
                  _onItemTapped(index);
                }
              },
              destinations: _bottomBarModules.length == 4
                  ? [
                      _moduleRegistry[_bottomBarModules[0]]!['destination'] as NavigationDestination,
                      _moduleRegistry[_bottomBarModules[1]]!['destination'] as NavigationDestination,
                      const NavigationDestination(
                        icon: Icon(Icons.apps_outlined, color: Colors.blueGrey),
                        selectedIcon: Icon(Icons.apps, color: Colors.blueGrey),
                        label: 'Menu',
                      ),
                      _moduleRegistry[_bottomBarModules[2]]!['destination'] as NavigationDestination,
                      _moduleRegistry[_bottomBarModules[3]]!['destination'] as NavigationDestination,
                    ]
                  : _bottomBarModules
                      .map((id) => _moduleRegistry[id]!['destination'] as NavigationDestination)
                      .toList(),
            ),
      ), // Close Scaffold
    ); // Close Theme
  }
}
