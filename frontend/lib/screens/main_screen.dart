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
import 'notification_history_screen.dart';
import '../services/update_service.dart';
import 'voice_assistant_screen.dart';
import 'sleep_tracker_screen.dart';
import 'astro_calendar_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../main.dart';

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
  List<String> _userMenuOrder = [];
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
    if (mounted) {
      UpdateService.checkForUpdates(context);
    }
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
        if (!firestoreModules.contains('astro_calendar')) {
          firestoreModules.add('astro_calendar');
        }
        
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
    final cachedMenuOrder = localPrefs.getStringList('user_menu_order') ?? [];

    if (mounted) {
      setState(() {
        _isDarkMode = isDark;
        if (cachedModulesStr != null) {
          _enabledModules = cachedModulesStr;
        }
        if (!_enabledModules.contains('astro_calendar')) {
          _enabledModules.add('astro_calendar');
        }
        _userSelectedBottomModules = cachedBottom;
        _userMenuOrder = cachedMenuOrder;
        _isLoading = false;
      });
    }

    try {
      final prefs = await StorageService().getUserPreferences();
      final firestoreModules = List<String>.from(prefs['enabledModules'] ?? ['gold']);
      if (!firestoreModules.contains('astro_calendar')) {
        firestoreModules.add('astro_calendar');
      }
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

      if (type.startsWith('CALENDAR_REMINDER')) {
        final parts = type.split('|');
        if (parts.length >= 3) {
          final reminderId = parts[1];
          final uid = parts[2];
          _showReminderActionDialog(reminderId, uid);
        } else {
          _selectTabOrPush('reminders');
        }
      } else {
        switch (type) {
          case 'GOLD_PRICE':
            _selectTabOrPush('gold');
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
      }
    });
  }

  Future<void> _showReminderActionDialog(String reminderId, String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('calendar_reminders')
          .doc(reminderId)
          .get();

      if (!doc.exists) {
        _selectTabOrPush('reminders');
        return;
      }

      final data = doc.data()!;
      final title = data['title'] ?? 'Reminder';
      final description = data['description'] ?? '';
      final snoozeEnabled = data['snoozeEnabled'] ?? false;
      final currentSnoozeCount = data['currentSnoozeCount'] ?? 0;
      final maxSnoozeCount = data['maxSnoozeCount'] ?? 3;
      final snoozeIntervalMinutes = data['snoozeIntervalMinutes'] ?? 15;

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.alarm, color: Colors.blueAccent),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (description.isNotEmpty) ...[
                Text(description, style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 16),
              ],
              Text(
                'Is this reminder done or do you want to snooze it?',
                style: TextStyle(color: Colors.grey[700]),
              ),
              if (snoozeEnabled) ...[
                const SizedBox(height: 8),
                Text(
                  'Snooze count: $currentSnoozeCount/$maxSnoozeCount (Interval: $snoozeIntervalMinutes mins)',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Close'),
            ),
            if (snoozeEnabled && currentSnoozeCount < maxSnoozeCount)
              ElevatedButton.icon(
                icon: const Icon(Icons.snooze, size: 16),
                label: const Text('Snooze'),
                onPressed: () async {
                  final nextTime = DateTime.now().add(Duration(minutes: snoozeIntervalMinutes));
                  final dateStr = "${nextTime.year}-${nextTime.month.toString().padLeft(2, '0')}-${nextTime.day.toString().padLeft(2, '0')}";
                  final timeStr = "${nextTime.hour.toString().padLeft(2, '0')}:${nextTime.minute.toString().padLeft(2, '0')}";

                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .collection('calendar_reminders')
                      .doc(reminderId)
                      .update({
                        'date': dateStr,
                        'time': timeStr,
                        'status': 'pending',
                        'currentSnoozeCount': currentSnoozeCount + 1,
                      });

                  if (dialogCtx.mounted) {
                    Navigator.pop(dialogCtx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Snoozed for $snoozeIntervalMinutes minutes.')),
                    );
                  }
                },
              ),
            ElevatedButton.icon(
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Done'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final expireAt = DateTime.now().add(const Duration(days: 30));
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .collection('calendar_reminders')
                    .doc(reminderId)
                    .update({
                      'status': 'completed',
                      'notifiedAt': FieldValue.serverTimestamp(),
                      'expireAt': Timestamp.fromDate(expireAt),
                    });

                if (dialogCtx.mounted) {
                  Navigator.pop(dialogCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reminder marked as completed!')),
                  );
                }
              },
            ),
          ],
        ),
      );
    } catch (e) {
      LogService.staticLog("Error showing reminder action dialog: $e");
      _selectTabOrPush('reminders');
    }
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
    themeNotifier.value = _isDarkMode ? ThemeMode.dark : ThemeMode.light;
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
    'sleep_tracker': {
      'screen': const SleepTrackerScreen(),
      'name': 'Sleep Tracker',
      'destination': const NavigationDestination(
        icon: Icon(Icons.bedtime_outlined, color: Colors.indigo),
        selectedIcon: Icon(Icons.bedtime, color: Colors.indigo),
        label: 'Sleep',
      ),
    },
    'astro_calendar': {
      'screen': const AstroCalendarScreen(),
      'name': 'Astro Calendar',
      'destination': const NavigationDestination(
        icon: Icon(Icons.sunny, color: Colors.orange),
        selectedIcon: Icon(Icons.wb_sunny, color: Colors.orange),
        label: 'Astro',
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
      dests.add(_buildDestination(active[i]));
    }
    if (dests.length <= mIdx) {
      dests.add(menuDest);
    }
    return dests;
  }

  NavigationDestination _buildDestination(String id) {
    final registry = _moduleRegistry[id]!;
    final dest = registry['destination'] as NavigationDestination;
    Widget icon = dest.icon;
    Widget? selectedIcon = dest.selectedIcon;

    if (id == 'notes') {
      icon = NavigationIconWithBadge(
        icon: icon,
        stream: StorageService().getIncomingRequestsStream('note'),
      );
      if (selectedIcon != null) {
        selectedIcon = NavigationIconWithBadge(
          icon: selectedIcon,
          stream: StorageService().getIncomingRequestsStream('note'),
        );
      }
    } else if (id == 'checklist') {
      icon = NavigationIconWithBadge(
        icon: icon,
        stream: StorageService().getIncomingRequestsStream('checklist'),
      );
      if (selectedIcon != null) {
        selectedIcon = NavigationIconWithBadge(
          icon: selectedIcon,
          stream: StorageService().getIncomingRequestsStream('checklist'),
        );
      }
    }

    return NavigationDestination(
      icon: icon,
      selectedIcon: selectedIcon,
      label: dest.label,
    );
  }

  bool _isModuleSelected(String id) {
    final active = _activeFeatures;
    if (_selectedIndex < active.length) {
      return active[_selectedIndex] == id;
    }
    return false;
  }

  void _openVoiceAssistant() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const VoiceAssistantScreen()),
    );
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

  Future<void> _saveMenuOrder(List<String> order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('user_menu_order', order);
    setState(() {
      _userMenuOrder = order;
    });
  }

  Widget _buildMenuItemTile(Map<String, dynamic> item) {
    return Container(
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
          _buildMenuIcon(item['id'] as String, item['icon'] as IconData, item['color'] as Color),
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
        return StatefulBuilder(
          builder: (context, setBottomSheetState) {
            final allItems = [
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
              // Checklist feature integrated directly into Notes
              if (_enabledModules.contains('shifts'))
                {
                  'id': 'shifts',
                  'name': 'My Shifts',
                  'icon': Icons.work_history,
                  'color': Colors.orange,
                  'action': () => _selectTabOrPush('shifts'),
                },
              if (_enabledModules.contains('events'))
                {
                  'id': 'events',
                  'name': 'Tech Events',
                  'icon': Icons.event,
                  'color': Colors.green,
                  'action': () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const MyShiftsScreen(initialTab: 1)),
                    );
                  },
                },
              if (_enabledModules.contains('walkin'))
                {
                  'id': 'walkin',
                  'name': 'Walk-In Drives',
                  'icon': Icons.directions_walk,
                  'color': Colors.lightBlue,
                  'action': () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const MyShiftsScreen(initialTab: 2)),
                    );
                  },
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
              if (_enabledModules.contains('sleep_tracker'))
                {
                  'id': 'sleep_tracker',
                  'name': 'Sleep Tracker',
                  'icon': Icons.bedtime,
                  'color': Colors.indigo,
                  'action': () => _selectTabOrPush('sleep_tracker'),
                },
              if (_enabledModules.contains('astro_calendar'))
                {
                  'id': 'astro_calendar',
                  'name': 'Astro Calendar',
                  'icon': Icons.sunny,
                  'color': Colors.orange,
                  'action': () => _selectTabOrPush('astro_calendar'),
                },
              if (_enabledModules.contains('voice_assistant'))
                {
                  'id': 'voice_assistant',
                  'name': 'Voice AI',
                  'icon': Icons.mic,
                  'color': Colors.redAccent,
                  'action': () {
                    _openVoiceAssistant();
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

            // Reorder based on _userMenuOrder
            final sortedItems = <Map<String, dynamic>>[];
            for (final id in _userMenuOrder) {
              final found = allItems.firstWhere((x) => x['id'] == id, orElse: () => {});
              if (found.isNotEmpty) {
                sortedItems.add(found);
              }
            }
            for (final item in allItems) {
              if (!sortedItems.any((x) => x['id'] == item['id'])) {
                sortedItems.add(item);
              }
            }

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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'App Menu',
                            style: GoogleFonts.outfit(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          Text(
                            'Long-press & drag to rearrange icons',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.95,
                    ),
                    itemCount: sortedItems.length,
                    itemBuilder: (context, index) {
                      final item = sortedItems[index];
                      final itemId = item['id'] as String;

                      return DragTarget<String>(
                        onAcceptWithDetails: (details) {
                          final draggedId = details.data;
                          if (draggedId != itemId) {
                            setBottomSheetState(() {
                              final draggedIdx = sortedItems.indexWhere((x) => x['id'] == draggedId);
                              final targetIdx = sortedItems.indexWhere((x) => x['id'] == itemId);
                              if (draggedIdx != -1 && targetIdx != -1) {
                                final temp = sortedItems[draggedIdx];
                                sortedItems[draggedIdx] = sortedItems[targetIdx];
                                sortedItems[targetIdx] = temp;
                                
                                final newOrder = sortedItems.map((x) => x['id'] as String).toList();
                                _saveMenuOrder(newOrder);
                              }
                            });
                          }
                        },
                        builder: (context, candidateData, rejectedData) {
                          final isOver = candidateData.isNotEmpty;
                          return LongPressDraggable<String>(
                            data: itemId,
                            feedback: Material(
                              color: Colors.transparent,
                              child: Container(
                                width: 100,
                                height: 95,
                                decoration: BoxDecoration(
                                  color: (item['color'] as Color).withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Icon(
                                    item['icon'] as IconData,
                                    color: Colors.white,
                                    size: 32,
                                  ),
                                ),
                              ),
                            ),
                            childWhenDragging: Opacity(
                              opacity: 0.3,
                              child: _buildMenuItemTile(item),
                            ),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              transform: isOver ? (Matrix4.identity()..scale(1.05)) : Matrix4.identity(),
                              child: InkWell(
                                onTap: () {
                                  Navigator.pop(context);
                                  (item['action'] as VoidCallback)();
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: _buildMenuItemTile(item),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            );
          },
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
  Widget _buildDesktopSidebar(List<String> activeModules, int displayIndex) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sidebarBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final borderCol = isDark ? Colors.white10 : Colors.black12;
    final activeColor = Theme.of(context).colorScheme.primary;
    final activeBg = activeColor.withOpacity(isDark ? 0.15 : 0.08);

    final active = activeModules;

    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: sidebarBg,
        border: Border(
          right: BorderSide(color: borderCol, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Sidebar Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Row(
              children: [
                Icon(Icons.alarm_add, color: activeColor, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'RemindBuddy',
                    style: GoogleFonts.pacifico(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: activeColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          
          // Navigation List
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    'DASHBOARD',
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                
                ...List.generate(active.length, (index) {
                  final id = active[index];
                  final registry = _moduleRegistry[id]!;
                  final name = registry['name'] as String;
                  final isSelected = displayIndex == index;
                  final dest = registry['destination'] as NavigationDestination;
                  
                  return Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    child: ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      selected: isSelected,
                      selectedTileColor: activeBg,
                      selectedColor: activeColor,
                      iconColor: Colors.grey,
                      textColor: isDark ? Colors.white70 : Colors.black87,
                      leading: _buildMenuIcon(id, (dest.icon as Icon).icon!, isSelected ? activeColor : Colors.grey),
                      title: Text(
                        name,
                        style: GoogleFonts.outfit(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                      onTap: () {
                        setState(() {
                          _selectedIndex = index;
                        });
                      },
                    ),
                  );
                }),
                
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    'OTHER UTILITIES',
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),

                if (_enabledModules.contains('daily_reminders'))
                  _buildSidebarItem(
                    icon: Icons.alarm_on,
                    color: Colors.blue,
                    title: 'Daily Reminders',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const DailyRemindersScreen()),
                      );
                    },
                  ),
                if (_enabledModules.contains('events'))
                  _buildSidebarItem(
                    icon: Icons.event,
                    color: Colors.green,
                    title: 'Tech Events',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const MyShiftsScreen(initialTab: 1)),
                      );
                    },
                  ),
                if (_enabledModules.contains('walkin'))
                  _buildSidebarItem(
                    icon: Icons.directions_walk,
                    color: Colors.lightBlue,
                    title: 'Walk-In Drives',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const MyShiftsScreen(initialTab: 2)),
                      );
                    },
                  ),
                if (_enabledModules.contains('voice_assistant'))
                  _buildSidebarItem(
                    icon: Icons.mic,
                    color: Colors.redAccent,
                    title: 'Voice Assistant',
                    onTap: _openVoiceAssistant,
                  ),

                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    'SYSTEM',
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),

                _buildSidebarItem(
                  icon: Icons.history_toggle_off,
                  color: Colors.deepPurple,
                  title: 'Notification History',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const NotificationHistoryScreen()),
                    );
                  },
                ),
                _buildSidebarItem(
                  icon: Icons.settings,
                  color: Colors.blueGrey,
                  title: 'Settings',
                  onTap: () {
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
                _buildSidebarItem(
                  icon: Icons.admin_panel_settings,
                  color: Colors.blueGrey,
                  title: 'Admin Console',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const AdminScreen()),
                    ).then((_) {
                      _loadPreferences();
                    });
                  },
                ),
              ],
            ),
          ),
          
          const Divider(height: 1),
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(_isDarkMode ? Icons.light_mode : Icons.dark_mode),
                      onPressed: _toggleTheme,
                      tooltip: _isDarkMode ? 'Light Mode' : 'Dark Mode',
                    ),
                    if (FirebaseAuth.instance.currentUser != null)
                      IconButton(
                        icon: const Icon(Icons.logout, color: Colors.redAccent),
                        onPressed: () async {
                          await FirebaseAuth.instance.signOut();
                          if (mounted) {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (context) => const AuthScreen()),
                            );
                          }
                        },
                        tooltip: 'Sign Out',
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'RemindBuddy v1.0.0',
                  style: GoogleFonts.outfit(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem({
    required IconData icon,
    required Color color,
    required String title,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        iconColor: Colors.grey,
        textColor: isDark ? Colors.white70 : Colors.black87,
        leading: Icon(icon, color: color, size: 20),
        title: Text(
          title,
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isLargeScreen = screenWidth >= 768;

    final activeModules = isLargeScreen
        ? _moduleRegistry.keys.toList()
        : _activeFeatures;

    if (_selectedIndex >= activeModules.length) {
      _selectedIndex = 0;
    }
    final int displayIndex = _selectedIndex;

    final mainBody = IndexedStack(
      index: displayIndex,
      children: activeModules
          .map((id) => _moduleRegistry[id]!['screen'] as Widget)
          .toList(),
    );

    if (isLargeScreen) {
      return Scaffold(
        body: Row(
          children: [
            _buildDesktopSidebar(activeModules, displayIndex),
            Expanded(
              child: mainBody,
            ),
          ],
        ),
      );
    }

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
        actions: [
          if (_enabledModules.contains('voice_assistant'))
            IconButton(
              icon: const Icon(Icons.mic, color: Colors.redAccent),
              onPressed: _openVoiceAssistant,
              tooltip: 'Voice Assistant',
            ),
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
            // Checklist feature integrated directly into Notes
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
            if (_enabledModules.contains('sleep_tracker'))
              ListTile(
                leading: const Icon(Icons.bedtime, color: Colors.indigo),
                title: const Text('Sleep Tracker'),
                selected: _isModuleSelected('sleep_tracker'),
                onTap: () {
                  Navigator.pop(context);
                  _selectTabOrPush('sleep_tracker');
                },
              ),
            if (_enabledModules.contains('astro_calendar'))
              ListTile(
                leading: const Icon(Icons.sunny, color: Colors.orange),
                title: const Text('Astro Calendar'),
                selected: _isModuleSelected('astro_calendar'),
                onTap: () {
                  Navigator.pop(context);
                  _selectTabOrPush('astro_calendar');
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
            if (_enabledModules.contains('events'))
              ListTile(
                leading: const Icon(Icons.event, color: Colors.green),
                title: const Text('Tech Events'),
                subtitle: const Text('Local tech events & meetups'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const MyShiftsScreen(initialTab: 1)),
                  );
                },
              ),
            if (_enabledModules.contains('walkin'))
              ListTile(
                leading: const Icon(Icons.directions_walk, color: Colors.lightBlue),
                title: const Text('Walk-In Drives'),
                subtitle: const Text('DevOps/Cloud/SRE interviews'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const MyShiftsScreen(initialTab: 2)),
                  );
                },
              ),
            if (_enabledModules.contains('voice_assistant'))
              ListTile(
                leading: const Icon(Icons.mic, color: Colors.redAccent),
                title: const Text('Voice Assistant'),
                subtitle: const Text('Ask Gemini anything'),
                onTap: () {
                  Navigator.pop(context);
                  _openVoiceAssistant();
                },
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.history_toggle_off, color: Colors.deepPurple),
              title: const Text('Notification History'),
              subtitle: const Text('Last 24 hours of notifications'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const NotificationHistoryScreen()),
                );
              },
            ),
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
              onTap: () async {
                Navigator.pop(context);
                final PackageInfo packageInfo = await PackageInfo.fromPlatform();
                if (context.mounted) {
                  showAboutDialog(
                    context: context,
                    applicationName: 'RemindBuddy',
                    applicationVersion: '${packageInfo.version}+${packageInfo.buildNumber}',
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
                }
              },
            ),
          ],
        ),
      ),
      body: mainBody,
      bottomNavigationBar: NavigationBar(
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
    );
  }

  Widget _buildMenuIcon(String id, IconData iconData, Color color) {
    Widget icon = Icon(
      iconData,
      color: color,
      size: 28,
    );
    if (id == 'notes') {
      return NavigationIconWithBadge(
        icon: icon,
        stream: StorageService().getIncomingRequestsStream('note'),
      );
    } else if (id == 'checklist') {
      return NavigationIconWithBadge(
        icon: icon,
        stream: StorageService().getIncomingRequestsStream('checklist'),
      );
    }
    return icon;
  }
}

class NavigationIconWithBadge extends StatelessWidget {
  final Widget icon;
  final Stream<List<Map<String, dynamic>>> stream;

  const NavigationIconWithBadge({
    super.key,
    required this.icon,
    required this.stream,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final hasRequests = snapshot.hasData && snapshot.data!.isNotEmpty;
        if (hasRequests) {
          return Badge(
            backgroundColor: Colors.red,
            child: icon,
          );
        }
        return icon;
      },
    );
  }
}
