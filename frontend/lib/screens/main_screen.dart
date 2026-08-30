import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'home_screen.dart';
import 'notes_screen.dart';
import 'reminders_screen.dart';
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
import '../services/finance_service.dart';
import '../services/vault_service.dart';
import 'vault_tab_wrapper.dart';
import 'settings_screen.dart';
import 'admin_screen.dart';
import 'notification_history_screen.dart';
import '../services/update_service.dart';
import '../services/home_widget_service.dart';
import 'voice_assistant_screen.dart';
import 'astro_calendar_screen.dart';
import 'gcp_cost_screen.dart';
import 'finance_screen.dart';
import 'job_assistant_screen.dart';
import 'tech_events_screen.dart';
import 'walkin_drives_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../main.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  String _activeFeatureOverride = 'home';
  bool _isDarkMode = false;
  List<String> _enabledModules = [
    'gold',
    'reminders',
    'notes',
    'shifts',
    'vault',
    'astro_calendar',
    'gcp_cost',
    'finance',
    'job_assistant',
    'daily_reminders',
    'events',
    'walkins',
    'voice_assistant',
  ];
  List<String> _userSelectedBottomModules = [];
  List<String> _userMenuOrder = [];
  List<String> _userFavoriteModules = ['gold', 'reminders', 'notes', 'shifts'];
  bool _isLoading = true;

  Future<void> _toggleFavorite(String id) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_userFavoriteModules.contains(id)) {
        _userFavoriteModules.remove(id);
      } else {
        _userFavoriteModules.add(id);
      }
    });
    await prefs.setStringList('user_favorite_modules', _userFavoriteModules);
  }

  bool get _isVaultEnabled => _enabledModules.contains('vault');

  StreamSubscription? _notificationSubscription;
  StreamSubscription? _authSubscription;
  StreamSubscription? _userPrefsSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadInitialData();
    _setupNotificationListener();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      _loadPreferences();
      _listenToUserPreferences();
      HomeWidgetService().syncAllWidgets();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      HomeWidgetService().syncAllWidgets();
    }
  }

  Future<void> _loadInitialData() async {
    await _loadPreferences();
    _listenToUserPreferences();
    _checkAstroNotification();
    FinanceService().initGlobalSmsListener();
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
        
        final localPrefs = await SharedPreferences.getInstance();
        await localPrefs.setStringList('cached_enabled_modules', firestoreModules);
        
        if (mounted) {
          setState(() {
            _enabledModules = firestoreModules;
          });
        }
      }
    }, onError: (err) {
      debugPrint("Error listening to user preferences: $err");
    });
  }

  Future<void> _loadPreferences() async {
    final localPrefs = await SharedPreferences.getInstance();
    final isDark = localPrefs.getBool('isDarkMode') ?? false;
    final cachedBottom = localPrefs.getStringList('user_bottom_modules') ?? [];
    final cachedModulesStr = localPrefs.getStringList('cached_enabled_modules');
    final cachedMenuOrder = localPrefs.getStringList('user_menu_order') ?? [];
    final cachedFavorites = localPrefs.getStringList('user_favorite_modules') ?? ['gold', 'reminders', 'notes', 'shifts'];

    if (mounted) {
      setState(() {
        _isDarkMode = isDark;
        if (cachedModulesStr != null) {
          _enabledModules = cachedModulesStr;
        }
        _userSelectedBottomModules = cachedBottom;
        _userMenuOrder = cachedMenuOrder;
        _userFavoriteModules = cachedFavorites;
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
      debugPrint("Error loading user preferences in background: $e");
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
          case 'astro_calendar':
            _selectTabOrPush('astro_calendar');
            break;
        }
      }
    });
  }

  Future<void> _checkAstroNotification() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (!_enabledModules.contains('astro_calendar')) return;

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (!doc.exists || doc.data() == null) return;
      final prefs = Map<String, dynamic>.from(doc.data()!['notificationPreferences'] ?? {});
      final bool astroNotifEnabled = prefs['astro_calendar'] ?? false;
      if (!astroNotifEnabled) return;

      final now = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(now);
      final sp = await SharedPreferences.getInstance();
      final lastNotified = sp.getString('last_astro_notif_date_${user.uid}');
      if (lastNotified == todayStr) return;

      final lunarEvent = AstroCalendarScreen.getTodayLunarEvent(now);
      if (lunarEvent != null) {
        await NotificationService().showNotification(
          id: 88899,
          title: lunarEvent['title']!,
          body: lunarEvent['body']!,
          channelId: 'calendar_reminder_channel',
          channelName: 'Astro Calendar Alerts',
          payload: 'astro_calendar',
        );
        await sp.setString('last_astro_notif_date_${user.uid}', todayStr);
      }
    } catch (e) {
      LogService().error("Error checking astro notification", e);
    }
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
                  }
                  if (mounted) {
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
                }
                if (mounted) {
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
    WidgetsBinding.instance.removeObserver(this);
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



  Map<String, Map<String, dynamic>> get _moduleRegistry => {
    'home': {
      'screen': HomeScreen(onNavigateToFeature: (id) => _selectTabOrPush(id)),
      'name': 'Home',
      'destination': const NavigationDestination(
        icon: Icon(Icons.home_outlined, color: Colors.blueAccent),
        selectedIcon: Icon(Icons.home, color: Colors.blueAccent),
        label: 'Home',
      ),
    },
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
      'screen': const RemindersScreen(),
      'name': 'Reminders',
      'destination': const NavigationDestination(
        icon: Icon(Icons.calendar_month_outlined, color: Colors.indigoAccent),
        selectedIcon: Icon(Icons.calendar_month, color: Colors.indigoAccent),
        label: 'Reminders',
      ),
    },
    'daily_reminders': {
      'screen': const DailyRemindersScreen(),
      'name': 'Daily Reminders',
      'destination': const NavigationDestination(
        icon: Icon(Icons.alarm_on_outlined, color: Colors.blue),
        selectedIcon: Icon(Icons.alarm_on, color: Colors.blue),
        label: 'Daily Tasks',
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
    'astro_calendar': {
      'screen': const AstroCalendarScreen(),
      'name': 'Astro Calendar',
      'destination': const NavigationDestination(
        icon: Icon(Icons.sunny, color: Colors.orange),
        selectedIcon: Icon(Icons.wb_sunny, color: Colors.orange),
        label: 'Astro',
      ),
    },
    'gcp_cost': {
      'screen': const GcpCostScreen(),
      'name': 'GCP Cost Tracker',
      'destination': const NavigationDestination(
        icon: Icon(Icons.attach_money_outlined, color: Colors.green),
        selectedIcon: Icon(Icons.attach_money, color: Colors.green),
        label: 'GCP Cost',
      ),
    },
    'finance': {
      'screen': const FinanceScreen(),
      'name': 'Finance',
      'destination': const NavigationDestination(
        icon: Icon(Icons.account_balance_wallet_outlined, color: Colors.teal),
        selectedIcon: Icon(Icons.account_balance_wallet, color: Colors.teal),
        label: 'Finance',
      ),
    },
    'job_assistant': {
      'screen': const JobAssistantScreen(),
      'name': 'AI Job Assistant',
      'destination': const NavigationDestination(
        icon: Icon(Icons.work_outline, color: Colors.blueAccent),
        selectedIcon: Icon(Icons.work, color: Colors.blueAccent),
        label: 'Job Assistant',
      ),
    },
    'events': {
      'screen': const TechEventsScreen(),
      'name': 'Tech Events',
      'destination': const NavigationDestination(
        icon: Icon(Icons.event_outlined, color: Colors.purpleAccent),
        selectedIcon: Icon(Icons.event, color: Colors.purpleAccent),
        label: 'Events',
      ),
    },
    'walkins': {
      'screen': const WalkInDrivesScreen(),
      'name': 'Walk-In Drives',
      'destination': const NavigationDestination(
        icon: Icon(Icons.directions_walk_outlined, color: Colors.deepOrange),
        selectedIcon: Icon(Icons.directions_walk, color: Colors.deepOrange),
        label: 'Walk-Ins',
      ),
    },
  };

  List<String> get _activeFeatures {
    final adminEnabled = _enabledModules
        .where((id) => _moduleRegistry.containsKey(id) && (id != 'vault' || _isVaultEnabled) && (!kIsWeb || id != 'checklist'))
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

  List<String> get _desktopActiveModules {
    return _enabledModules
        .where((id) => _moduleRegistry.containsKey(id) && (id != 'vault' || _isVaultEnabled) && (!kIsWeb || id != 'checklist'))
        .toList();
  }

  int get _menuIndex {
    final active = _activeFeatures;
    if (active.length >= 4) return 2;
    if (active.length == 3) return 2;
    if (active.length == 2) return 1;
    if (active.length == 1) return 1;
    return 0;
  }

  bool get _isBottomBarFeatureActive {
    final active = _activeFeatures;
    return active.contains(_activeFeatureOverride);
  }

  int get _navBarSelectedIndex {
    final active = _activeFeatures;
    if (active.isEmpty) return 0;
    final mIdx = _menuIndex;
    
    int tempIdx = active.indexOf(_activeFeatureOverride);
    if (tempIdx == -1) {
      return 0;
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

    final menuColor = _isDarkMode ? Colors.white70 : Colors.blueGrey;
    final menuDest = NavigationDestination(
      icon: Icon(Icons.apps_outlined, color: menuColor),
      selectedIcon: Icon(Icons.apps, color: menuColor),
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

    if (id == 'reminders') {
      final Color remColor = _isDarkMode ? Colors.indigoAccent : Colors.indigo;
      icon = Icon(Icons.calendar_month_outlined, color: remColor);
      selectedIcon = Icon(Icons.calendar_month, color: remColor);
    } else if (id == 'daily_reminders') {
      final Color dailyColor = _isDarkMode ? Colors.blueAccent : Colors.blue;
      icon = Icon(Icons.alarm_on_outlined, color: dailyColor);
      selectedIcon = Icon(Icons.alarm_on, color: dailyColor);
    } else if (id == 'notes') {
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
    } else if (id == 'vault') {
      icon = NavigationIconWithBadge(
        icon: icon,
        stream: VaultService().getIncomingRequestsStream(),
      );
      if (selectedIcon != null) {
        selectedIcon = NavigationIconWithBadge(
          icon: selectedIcon,
          stream: VaultService().getIncomingRequestsStream(),
        );
      }
    }

    return NavigationDestination(
      icon: icon,
      selectedIcon: _isBottomBarFeatureActive ? selectedIcon : icon,
      label: dest.label,
    );
  }


  void _openVoiceAssistant() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const VoiceAssistantScreen()),
    );
  }

  void _selectTabOrPush(String id) {
    if (id == 'voice_assistant') {
      _openVoiceAssistant();
      return;
    } else if (id == 'notifications') {
      Navigator.push(context, MaterialPageRoute(builder: (context) => const NotificationHistoryScreen()));
      return;
    } else if (id == 'settings') {
      Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen()));
      return;
    } else if (id == 'bank_accounts') {
      Navigator.push(context, MaterialPageRoute(builder: (context) => const FinanceScreen(initialFeatureIndex: 0)));
      return;
    } else if (id == 'expenses') {
      Navigator.push(context, MaterialPageRoute(builder: (context) => const FinanceScreen(initialFeatureIndex: 4)));
      return;
    } else if (id == 'gold_price' || id == 'gold_rates') {
      id = 'gold';
    } else if (id == 'events_walkins' || id == 'tech_events') {
      id = 'events';
    } else if (id == 'walkin' || id == 'walkin_drives' || id == 'walkins') {
      id = 'walkins';
    } else if (id == 'job_discovery' || id == 'job_assistant') {
      id = 'job_assistant';
    } else if (id == 'quick_notes') {
      id = 'notes';
    }

    final active = _activeFeatures;
    final idx = active.indexOf(id);
    if (idx != -1) {
      setState(() {
        _selectedIndex = idx;
        _activeFeatureOverride = id;
      });
    } else if (_moduleRegistry.containsKey(id)) {
      setState(() {
        _activeFeatureOverride = id;
      });
    }
  }

  void _showCustomizeBottomBarDialog() async {
    final adminEnabled = _enabledModules.where((id) => _moduleRegistry.containsKey(id) && (id != 'vault' || _isVaultEnabled) && (!kIsWeb || id != 'checklist')).toList();
    List<String> tempSelected = List<String>.from(_activeFeatures);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.dashboard_customize_rounded, color: Theme.of(context).primaryColor, size: 24),
                  const SizedBox(width: 10),
                  const Text('Customize Bottom Bar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select features (up to 4) to show in your bottom navigation bar:',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 340),
                      child: Scrollbar(
                        thumbVisibility: true,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: adminEnabled.length,
                          itemBuilder: (context, index) {
                            final id = adminEnabled[index];
                            final isChecked = tempSelected.contains(id);
                            final label = _moduleRegistry[id]?['name'] ?? id.toUpperCase();
                            final iconData = _moduleRegistry[id]?['icon'] as IconData? ?? Icons.star_rounded;
                            final color = _moduleRegistry[id]?['color'] as Color? ?? Colors.blueAccent;

                            return CheckboxListTile(
                              secondary: CircleAvatar(
                                radius: 15,
                                backgroundColor: color.withValues(alpha: 0.15),
                                child: Icon(iconData, color: color, size: 16),
                              ),
                              title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                              value: isChecked,
                              activeColor: Theme.of(context).colorScheme.primary,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
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
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
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
        color: (item['color'] as Color).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (item['color'] as Color).withValues(alpha: 0.15),
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
                  'name': 'Calendar Reminders',
                  'icon': Icons.calendar_month,
                  'color': Colors.indigo,
                  'action': () => _selectTabOrPush('reminders'),
                },
              if (_enabledModules.contains('daily_reminders'))
                {
                  'id': 'daily_reminders',
                  'name': 'Daily Reminders',
                  'icon': Icons.alarm_on,
                  'color': Colors.blue,
                  'action': () => _selectTabOrPush('daily_reminders'),
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
                  'action': () => _selectTabOrPush('events'),
                },
              if (_enabledModules.contains('walkin') || _enabledModules.contains('walkins'))
                {
                  'id': 'walkins',
                  'name': 'Walk-In Drives',
                  'icon': Icons.directions_walk,
                  'color': Colors.lightBlue,
                  'action': () => _selectTabOrPush('walkins'),
                },
              if (_isVaultEnabled)
                {
                  'id': 'vault',
                  'name': 'Secure Vault',
                  'icon': Icons.shield,
                  'color': Colors.blueAccent,
                  'action': () => _selectTabOrPush('vault'),
                },
              if (_enabledModules.contains('astro_calendar'))
                {
                  'id': 'astro_calendar',
                  'name': 'Astro Calendar',
                  'icon': Icons.sunny,
                  'color': Colors.orange,
                  'action': () => _selectTabOrPush('astro_calendar'),
                },
              if (_enabledModules.contains('gcp_cost'))
                {
                  'id': 'gcp_cost',
                  'name': 'GCP Cost Tracker',
                  'icon': Icons.account_balance_wallet,
                  'color': Colors.green,
                  'action': () => _selectTabOrPush('gcp_cost'),
                },
              if (_enabledModules.contains('job_assistant'))
                {
                  'id': 'job_assistant',
                  'name': 'AI Job Assistant',
                  'icon': Icons.work_outline,
                  'color': Colors.blueAccent,
                  'action': () => _selectTabOrPush('job_assistant'),
                },
              {
                'id': 'finance',
                'name': 'Finance',
                'icon': Icons.account_balance_wallet_outlined,
                'color': Colors.teal,
                'action': () => _selectTabOrPush('finance'),
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
                'id': 'home',
                'name': 'Home',
                'icon': Icons.home,
                'color': Colors.blueAccent,
                'action': () => _selectTabOrPush('home'),
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
                        color: Colors.grey.withValues(alpha: 0.3),
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
                                  color: (item['color'] as Color).withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: const [
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
                              transform: isOver ? Matrix4.diagonal3Values(1.05, 1.05, 1.0) : Matrix4.identity(),
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
    final active = _activeFeatures;
    if (index >= 0 && index < active.length) {
      setState(() {
        _selectedIndex = index;
        _activeFeatureOverride = active[index];
      });
    }
  }

  Widget _buildDesktopSidebar(List<String> desktopModules, int displayIndex) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sidebarBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final borderCol = isDark ? Colors.white10 : Colors.black12;
    final activeColor = Theme.of(context).colorScheme.primary;
    final activeBg = activeColor.withValues(alpha: isDark ? 0.15 : 0.08);

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
                // FAVORITES SECTION
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    '⭐ FAVORITES',
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                
                ...desktopModules.where((id) => _userFavoriteModules.contains(id)).map((id) {
                  final index = desktopModules.indexOf(id);
                  final registry = _moduleRegistry[id]!;
                  final name = registry['name'] as String;
                  final isSelected = displayIndex == index;
                  final dest = registry['destination'] as NavigationDestination;
                  final vibrantColor = (dest.icon as Icon).color ?? activeColor;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    child: ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      selected: isSelected,
                      selectedTileColor: activeBg,
                      selectedColor: activeColor,
                      textColor: isDark ? Colors.white70 : Colors.black87,
                      leading: _buildMenuIcon(id, (dest.icon as Icon).icon!, vibrantColor),
                      title: Text(
                        name,
                        style: GoogleFonts.outfit(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.star, color: Colors.amber, size: 18),
                        onPressed: () => _toggleFavorite(id),
                        tooltip: 'Remove from Favorites',
                      ),
                      onTap: () {
                        setState(() {
                          _selectedIndex = index;
                        });
                      },
                    ),
                  );
                }),

                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),

                // OTHER FEATURES SECTION
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    '📌 OTHER FEATURES',
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),

                ...desktopModules.where((id) => !_userFavoriteModules.contains(id)).map((id) {
                  final index = desktopModules.indexOf(id);
                  final registry = _moduleRegistry[id]!;
                  final name = registry['name'] as String;
                  final isSelected = displayIndex == index;
                  final dest = registry['destination'] as NavigationDestination;
                  final vibrantColor = (dest.icon as Icon).color ?? activeColor;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    child: ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      selected: isSelected,
                      selectedTileColor: activeBg,
                      selectedColor: activeColor,
                      textColor: isDark ? Colors.white70 : Colors.black87,
                      leading: _buildMenuIcon(id, (dest.icon as Icon).icon!, vibrantColor),
                      title: Text(
                        name,
                        style: GoogleFonts.outfit(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.star_border, color: Colors.grey, size: 18),
                        onPressed: () => _toggleFavorite(id),
                        tooltip: 'Add to Favorites',
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
                    onTap: () => _selectTabOrPush('daily_reminders'),
                  ),
                if (_enabledModules.contains('events'))
                  _buildSidebarItem(
                    icon: Icons.event,
                    color: Colors.green,
                    title: 'Tech Events',
                    onTap: () {
                      Navigator.pop(context);
                      _selectTabOrPush('events');
                    },
                  ),
                if (_enabledModules.contains('walkin') || _enabledModules.contains('walkins'))
                  _buildSidebarItem(
                    icon: Icons.directions_walk,
                    color: Colors.lightBlue,
                    title: 'Walk-In Drives',
                    onTap: () {
                      Navigator.pop(context);
                      _selectTabOrPush('walkins');
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

    if (isLargeScreen) {
      final desktopModules = _desktopActiveModules;
      if (_selectedIndex >= desktopModules.length) {
        _selectedIndex = 0;
      }
      final int displayIndex = _selectedIndex;

      final desktopMainBody = IndexedStack(
        index: displayIndex,
        children: desktopModules
            .map((id) => _moduleRegistry[id]!['screen'] as Widget)
            .toList(),
      );

      return Scaffold(
        body: Row(
          children: [
            _buildDesktopSidebar(desktopModules, displayIndex),
            Expanded(
              child: desktopMainBody,
            ),
          ],
        ),
      );
    }

    final activeModules = _activeFeatures;
    Widget mainBody;
    if (_moduleRegistry.containsKey(_activeFeatureOverride)) {
      mainBody = _moduleRegistry[_activeFeatureOverride]!['screen'] as Widget;
    } else if (_selectedIndex < activeModules.length) {
      mainBody = _moduleRegistry[activeModules[_selectedIndex]]!['screen'] as Widget;
    } else {
      mainBody = HomeScreen(onNavigateToFeature: (id) => _selectTabOrPush(id));
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
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

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
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
              title: const Text('Log Out', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              subtitle: Text(
                FirebaseAuth.instance.currentUser?.email ?? 'Signed in',
                style: TextStyle(fontSize: 11, color: _isDarkMode ? Colors.white54 : Colors.black54),
              ),
              onTap: () async {
                Navigator.pop(context);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: Row(
                      children: [
                        const Icon(Icons.logout_rounded, color: Colors.redAccent),
                        const SizedBox(width: 8),
                        Text('Log Out', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    content: const Text('Are you sure you want to log out of RemindBuddy?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Log Out'),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  await FirebaseAuth.instance.signOut();
                  if (context.mounted) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (context) => const AuthScreen()),
                      (route) => false,
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
      body: mainBody,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navBarSelectedIndex,
        indicatorColor: _isBottomBarFeatureActive ? null : Colors.transparent,
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
    } else if (id == 'vault') {
      return NavigationIconWithBadge(
        icon: icon,
        stream: VaultService().getIncomingRequestsStream(),
      );
    }
    return icon;
  }
}

class NavigationIconWithBadge extends StatelessWidget {
  final Widget icon;
  final Stream<dynamic> stream;

  const NavigationIconWithBadge({
    super.key,
    required this.icon,
    required this.stream,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<dynamic>(
      stream: stream,
      builder: (context, snapshot) {
        final List items = snapshot.hasData && snapshot.data is List ? (snapshot.data as List) : [];
        final count = items.length;
        if (count > 0) {
          return Badge(
            backgroundColor: Colors.red,
            label: Text('$count'),
            child: icon,
          );
        }
        return icon;
      },
    );
  }
}
