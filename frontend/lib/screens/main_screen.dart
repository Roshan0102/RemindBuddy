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
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/log_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import 'vault_tab_wrapper.dart';
import 'settings_screen.dart';
import 'notification_control_screen.dart';
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
  StreamSubscription? _userPrefsSubscription;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _setupNotificationListener();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      _loadPreferences();
      _listenToUserPreferences();
    });
  }

  Future<void> _loadInitialData() async {
    await _loadPreferences();
    _listenToUserPreferences();
  }

  void _listenToUserPreferences() {
    _userPrefsSubscription?.cancel();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _userPrefsSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) async {
      if (snapshot.exists && snapshot.data() != null) {
        final data = snapshot.data()!;
        final firestoreModules = List<String>.from(data['enabledModules'] ?? ['gold']);
        
        final localPrefs = await SharedPreferences.getInstance();
        await localPrefs.setStringList('cached_enabled_modules', firestoreModules);
        
        if (mounted) {
          setState(() {
            _enabledModules = firestoreModules;
          });
        }
      }
    }, onError: (err) {
      print("Error listening to user preferences: $err");
    });
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
    _userPrefsSubscription?.cancel();
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

  List<String> get _activeFeatures {
    final adminEnabled = _enabledModules
        .where((id) => _moduleRegistry.containsKey(id) && (id != 'vault' || _isVaultEnabled))
        .toList();

    final activeUserSelected = _userSelectedBottomModules
        .where((id) => adminEnabled.contains(id))
        .toList();

    final List<String> result = [];
    result.addAll(activeUserSelected);

    for (var id in adminEnabled) {
      if (result.length >= 4) break;
      if (!result.contains(id)) {
        result.add(id);
      }
    }

    return result;
  }

  int get _menuIndex {
    final active = _activeFeatures;
    if (active.length >= 4) return 2;
    if (active.length == 3) return 2;
    if (active.length == 2) return 1;
    if (active.length == 1) return 1;
    return 0;
  }

  int get _navBarSelectedIndex {
    final active = _activeFeatures;
    if (active.isEmpty) return 0;
    final mIdx = _menuIndex;
    
    int tempIdx = _selectedIndex;
    if (tempIdx >= active.length) {
      tempIdx = 0;
    }
    
    if (tempIdx < mIdx) {
      return tempIdx;
    } else {
      return tempIdx + 1;
    }
  }

  List<NavigationDestination> get _navBarDestinations {
    final active = _activeFeatures;
    final List<NavigationDestination> dests = [];
    final mIdx = _menuIndex;

    const menuDest = NavigationDestination(
      icon: Icon(Icons.apps_outlined, color: Colors.blueGrey),
      selectedIcon: Icon(Icons.apps, color: Colors.blueGrey),
      label: 'Menu',
    );

    for (int i = 0; i < active.length; i++) {
      if (i == mIdx) {
        dests.add(menuDest);
      }
      dests.add(_moduleRegistry[active[i]]!['destination'] as NavigationDestination);
    }
    if (dests.length <= mIdx) {
      dests.add(menuDest);
    }
    return dests;
  }

  bool _isModuleSelected(String id) {
    final active = _activeFeatures;
    if (_selectedIndex < active.length) {
      return active[_selectedIndex] == id;
    }
    return false;
  }

  void _selectTabOrPush(String id) {
    final active = _activeFeatures;
    final idx = active.indexOf(id);
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
    List<String> tempSelected = List<String>.from(_activeFeatures);

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
                  const Text('Select features (up to 4) to show in the bottom navigation bar:'),
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
          if (_enabledModules.contains('reminders'))
            {
              'id': 'reminders',
              'name': 'Reminders',
              'icon': Icons.calendar_today,
              'color': Colors.indigo,
              'action': () => _selectTabOrPush('reminders'),
            },
          if (_enabledModules.contains('gold'))
            {
              'id': 'gold',
              'name': 'Gold Rates',
              'icon': Icons.monetization_on,
              'color': Colors.amber,
              'action': () => _selectTabOrPush('gold'),
            },
          if (_enabledModules.contains('notes'))
            {
              'id': 'notes',
              'name': 'Notes',
              'icon': Icons.note_alt,
              'color': Colors.teal,
              'action': () => _selectTabOrPush('notes'),
            },
          if (_enabledModules.contains('checklist'))
            {
              'id': 'checklist',
              'name': 'Checklist',
              'icon': Icons.playlist_add_check_outlined,
              'color': Colors.blue,
              'action': () => _selectTabOrPush('checklist'),
            },
          if (_enabledModules.contains('shifts'))
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
          if (_enabledModules.contains('daily_reminders'))
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
              if (_enabledModules.contains('checklist')) ...[
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
              ],
              if (_enabledModules.contains('reminders'))
                ListTile(
                  leading: const Icon(Icons.calendar_today, color: Colors.indigo),
                  title: const Text('Reminders'),
                  selected: _isModuleSelected('reminders'),
                  onTap: () {
                    Navigator.pop(context);
                    _selectTabOrPush('reminders');
                  },
                ),
              if (_enabledModules.contains('notes'))
                ListTile(
                  leading: const Icon(Icons.note_alt, color: Colors.teal),
                  title: const Text('Notes'),
                  selected: _isModuleSelected('notes'),
                  onTap: () {
                    Navigator.pop(context);
                    _selectTabOrPush('notes');
                  },
                ),
              if (_enabledModules.contains('gold'))
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
              if (_enabledModules.contains('daily_reminders'))
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
              if (_enabledModules.contains('shifts'))
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
              ],
              const Divider(),
              ListTile(
                leading: const Icon(Icons.settings, color: Colors.blueGrey),
                title: const Text('Settings'),
                subtitle: const Text('Profile, Bottom Bar & Notifications'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SettingsScreen()),
                  ).then((result) {
                    if (result == 'customize_bottom_bar') {
                      _showCustomizeBottomBarDialog();
                    }
                    setState(() {});
                    _loadPreferences();
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.notifications_active, color: Colors.amber),
                title: const Text('Notification Control'),
                subtitle: const Text('Configure push notifications'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const NotificationControlScreen()),
                  );
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
                leading: const Icon(Icons.info_outline),
                title: const Text('About'),
                onTap: () {
                  Navigator.pop(context);
                  showAboutDialog(
                    context: context,
                    applicationName: 'RemindBuddy',
                    applicationVersion: '1.5.1',
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
              index: _selectedIndex < _activeFeatures.length ? _selectedIndex : 0,
              children: _activeFeatures
                  .map((id) => _moduleRegistry[id]!['screen'] as Widget)
                  .toList(),
            ),
        bottomNavigationBar: _isLoading 
          ? null 
          : NavigationBar(
              selectedIndex: _navBarSelectedIndex,
              onDestinationSelected: (int index) {
                final active = _activeFeatures;
                final mIdx = _menuIndex;
                if (index == mIdx) {
                  _showAppMenuBottomSheet();
                } else {
                  int targetIndex = index < mIdx ? index : index - 1;
                  if (targetIndex >= 0 && targetIndex < active.length) {
                    _onItemTapped(targetIndex);
                  }
                }
              },
              destinations: _navBarDestinations,
            ),
      ), // Close Scaffold
    ); // Close Theme
  }
}
