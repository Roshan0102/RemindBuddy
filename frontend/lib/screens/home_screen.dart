import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../services/gold_price_service.dart';
import '../services/home_widget_service.dart';
import '../services/app_permission_service.dart';
import '../models/gold_price.dart';

class HomeScreen extends StatefulWidget {
  final Function(String featureId)? onNavigateToFeature;

  const HomeScreen({super.key, this.onNavigateToFeature});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GoldPriceService _goldPriceService = GoldPriceService();

  // User's active enabled modules from Firestore/Preferences
  List<String> _enabledModules = ['gold', 'finance', 'shifts', 'reminders', 'notes'];
  
  // Static Weather Cache across Screen Mounts (avoids re-fetching on tab/screen switch)
  static DateTime? _lastWeatherFetchTime;
  static String _cachedCity = 'Bengaluru';
  static String _cachedTemp = '--°C';
  static String _cachedCondition = 'Partly Cloudy';
  static IconData _cachedIcon = Icons.wb_sunny_rounded;

  // Custom dashboard widget list chosen by user (weather is in permanent top header)
  List<String> _activeWidgets = ['gold_price', 'bank_accounts', 'expenses', 'shifts', 'voice_assistant'];
  String _heroWidget = 'gold_price'; // Default hero card

  bool _isLoading = true;

  // Live Data State
  GoldPrice? _latestGoldPrice;
  List<Map<String, dynamic>> _bankAccounts = [];
  double _totalBalance = 0.0;
  double _todayCredited = 0.0;
  double _todayDebited = 0.0;
  String _activeBankName = 'Active Accounts';
  Map<String, dynamic>? _todayShift;
  int _todayEventsCount = 0;
  int _todayWalkinsCount = 0;
  int _todayRemindersCount = 0;
  int _dailyRemindersCount = 0;
  int _totalNotesCount = 0;

  // Weather state (initialized from static cache)
  String _weatherTemp = _cachedTemp;
  String _weatherCity = _cachedCity;
  String _weatherCondition = _cachedCondition;
  IconData _weatherIcon = _cachedIcon;

  // Firestore Subscriptions
  StreamSubscription? _userDocSub;
  StreamSubscription? _goldSub;
  StreamSubscription? _accountsSub;
  StreamSubscription? _txSub;
  StreamSubscription? _smsTxSub;
  StreamSubscription? _eventsSub;
  StreamSubscription? _walkinsSub;
  StreamSubscription? _shiftsSub;
  StreamSubscription? _remindersSub;
  StreamSubscription? _notesSub;
  StreamSubscription? _dailyRemindersSub;
  Timer? _widgetSyncTimer;

  final Map<String, Map<String, dynamic>> _widgetMetadata = {
    'gold_price': {
      'title': 'Gold Rates (22K)',
      'module': 'gold',
      'icon': Icons.monetization_on_rounded,
      'color': Colors.amber,
    },
    'bank_accounts': {
      'title': 'Bank Balances',
      'module': 'finance',
      'icon': Icons.account_balance_rounded,
      'color': Colors.lightBlueAccent,
    },
    'expenses': {
      'title': 'Cashflow Today',
      'module': 'finance',
      'icon': Icons.swap_horiz_rounded,
      'color': Colors.tealAccent,
    },
    'shifts': {
      'title': 'Work Roster',
      'module': 'shifts',
      'icon': Icons.calendar_month_rounded,
      'color': Colors.deepPurpleAccent,
    },
    'reminders': {
      'title': 'Reminders',
      'module': 'reminders',
      'icon': Icons.notifications_active_rounded,
      'color': Colors.orangeAccent,
    },
    'notes': {
      'title': 'Quick Notes',
      'module': 'notes',
      'icon': Icons.edit_note_rounded,
      'color': Colors.purpleAccent,
    },
    'tech_events': {
      'title': 'Tech Events',
      'module': 'all',
      'icon': Icons.event_available_rounded,
      'color': Colors.indigoAccent,
    },
    'walkin_drives': {
      'title': 'Walk-in Drives',
      'module': 'all',
      'icon': Icons.work_outline_rounded,
      'color': Colors.cyanAccent,
    },
    'job_discovery': {
      'title': 'AI Job Discovery',
      'module': 'all',
      'icon': Icons.rocket_launch_rounded,
      'color': Colors.blueAccent,
    },
    'voice_assistant': {
      'title': 'Ask Buddy (Voice AI)',
      'module': 'all',
      'icon': Icons.mic_rounded,
      'color': Colors.redAccent,
    },
  };

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _loadDashboardData();
    _fetchWeather();
    HomeWidgetService().syncAllWidgets();
    // Periodic sync every 45 seconds to keep home screen Android widgets fresh
    _widgetSyncTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      HomeWidgetService().syncAllWidgets();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppPermissionService().checkAndPromptInitialPermissions(context);
    });
  }

  @override
  void dispose() {
    _widgetSyncTimer?.cancel();
    _userDocSub?.cancel();
    _goldSub?.cancel();
    _accountsSub?.cancel();
    _txSub?.cancel();
    _smsTxSub?.cancel();
    _eventsSub?.cancel();
    _walkinsSub?.cancel();
    _shiftsSub?.cancel();
    _remindersSub?.cancel();
    _notesSub?.cancel();
    _dailyRemindersSub?.cancel();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedModules = prefs.getStringList('cached_enabled_modules');
    final savedWidgets = prefs.getStringList('dashboard_active_widgets');
    final savedHero = prefs.getString('dashboard_hero_widget');

    // Restore cached weather to eliminate initial --°C flicker
    final cachedCity = prefs.getString('cached_weather_city');
    final cachedTemp = prefs.getString('cached_weather_temp');
    final cachedCond = prefs.getString('cached_weather_cond');
    final cachedIconCode = prefs.getInt('cached_weather_icon_code');
    if (cachedCity != null && cachedTemp != null) {
      _cachedCity = cachedCity;
      _cachedTemp = cachedTemp;
      _cachedCondition = cachedCond ?? 'Partly Cloudy';
      if (cachedIconCode != null) {
        _cachedIcon = _resolveWeatherIconFromCode(cachedIconCode);
      }
      _weatherCity = _cachedCity;
      _weatherTemp = _cachedTemp;
      _weatherCondition = _cachedCondition;
      _weatherIcon = _cachedIcon;
    }

    if (cachedModules != null && cachedModules.isNotEmpty) {
      _enabledModules = cachedModules;
    }

    if (savedWidgets != null && savedWidgets.isNotEmpty) {
      _activeWidgets = savedWidgets.where(_isWidgetAllowed).toList();
    } else {
      _computeDefaultActiveWidgets();
    }

    if (savedHero != null && _isWidgetAllowed(savedHero)) {
      _heroWidget = savedHero;
    } else {
      _heroWidget = _activeWidgets.isNotEmpty ? _activeWidgets.first : 'gold_price';
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  static IconData _resolveWeatherIconFromCode(int code) {
    if (code == Icons.wb_sunny_rounded.codePoint) return Icons.wb_sunny_rounded;
    if (code == Icons.wb_cloudy_rounded.codePoint) return Icons.wb_cloudy_rounded;
    if (code == Icons.thunderstorm_rounded.codePoint) return Icons.thunderstorm_rounded;
    if (code == Icons.grain_rounded.codePoint) return Icons.grain_rounded;
    if (code == Icons.ac_unit_rounded.codePoint) return Icons.ac_unit_rounded;
    return Icons.wb_sunny_rounded;
  }

  bool _isWidgetAllowed(String widgetKey) {
    final meta = _widgetMetadata[widgetKey];
    if (meta == null) return false;
    final requiredMod = meta['module'] as String;
    if (requiredMod == 'all') return true;
    return _enabledModules.contains(requiredMod);
  }

  void _computeDefaultActiveWidgets() {
    final List<String> list = [];
    for (final entry in _widgetMetadata.entries) {
      if (_isWidgetAllowed(entry.key)) {
        list.add(entry.key);
      }
    }
    _activeWidgets = list;
    if (!_activeWidgets.contains(_heroWidget)) {
      _heroWidget = _activeWidgets.isNotEmpty ? _activeWidgets.first : 'gold_price';
    }
  }

  Future<void> _saveDashboardConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('dashboard_active_widgets', _activeWidgets);
    await prefs.setString('dashboard_hero_widget', _heroWidget);
  }

  void _swapCards(String sourceKey, String targetKey) {
    if (sourceKey == targetKey) return;
    setState(() {
      final sourceIndex = _activeWidgets.indexOf(sourceKey);
      final targetIndex = _activeWidgets.indexOf(targetKey);
      if (sourceIndex != -1 && targetIndex != -1) {
        final temp = _activeWidgets[sourceIndex];
        _activeWidgets[sourceIndex] = _activeWidgets[targetIndex];
        _activeWidgets[targetIndex] = temp;
        _heroWidget = _activeWidgets.first;
      }
    });
    _saveDashboardConfig();
    HapticFeedback.mediumImpact();

    final sourceTitle = _widgetMetadata[sourceKey]?['title'] ?? sourceKey;
    final targetTitle = _widgetMetadata[targetKey]?['title'] ?? targetKey;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Reordered: $sourceTitle ⇄ $targetTitle',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _fetchWeather({bool force = false}) async {
    // 5-minute cache throttle to prevent re-fetching on tab/screen switch
    if (!force && _lastWeatherFetchTime != null) {
      final diff = DateTime.now().difference(_lastWeatherFetchTime!);
      if (diff < const Duration(minutes: 5) && _weatherTemp != '--°C') {
        return;
      }
    }

    try {
      double lat = 12.9716; // default Bengaluru
      double lon = 77.5946;
      String city = _weatherCity.isNotEmpty && _weatherCity != 'Bengaluru' ? _weatherCity : 'Bengaluru';

      try {
        final ipRes = await http.get(Uri.parse('http://ip-api.com/json')).timeout(const Duration(seconds: 3));
        if (ipRes.statusCode == 200) {
          final ipData = json.decode(ipRes.body);
          if (ipData['status'] == 'success') {
            lat = (ipData['lat'] as num).toDouble();
            lon = (ipData['lon'] as num).toDouble();
            city = ipData['city']?.toString() ?? 'Bengaluru';
          }
        }
      } catch (_) {}

      final response = await http
          .get(Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current_weather=true'))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final current = data['current_weather'];
        final temp = (current['temperature'] as num).round();
        final code = (current['weathercode'] as num).toInt();

        String condition = 'Sunny';
        IconData icon = Icons.wb_sunny_rounded;

        if (code == 0) {
          condition = 'Clear Sky';
          icon = Icons.wb_sunny_rounded;
        } else if (code >= 1 && code <= 3) {
          condition = 'Partly Cloudy';
          icon = Icons.cloud_rounded;
        } else if (code >= 51 && code <= 67) {
          condition = 'Rain Showers';
          icon = Icons.grain_rounded;
        } else if (code >= 80 && code <= 99) {
          condition = 'Thunderstorm';
          icon = Icons.thunderstorm_rounded;
        }

        _lastWeatherFetchTime = DateTime.now();
        _cachedCity = city;
        _cachedTemp = '$temp°C';
        _cachedCondition = condition;
        _cachedIcon = icon;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_weather_city', city);
        await prefs.setString('cached_weather_temp', '$temp°C');
        await prefs.setString('cached_weather_cond', condition);
        await prefs.setInt('cached_weather_icon_code', icon.codePoint);

        if (mounted) {
          setState(() {
            _weatherCity = city;
            _weatherTemp = '$temp°C';
            _weatherCondition = condition;
            _weatherIcon = icon;
          });
        }
      }
    } catch (_) {}
  }

  void _loadDashboardData() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // 0. Listen to User's allowed modules from Firestore
    _userDocSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        final data = snapshot.data()!;
        final mods = List<String>.from(data['enabledModules'] ?? ['gold']);
        if (mounted) {
          setState(() {
            _enabledModules = mods;
            _activeWidgets.removeWhere((w) => !_isWidgetAllowed(w));
            if (!_isWidgetAllowed(_heroWidget)) {
              _heroWidget = _activeWidgets.isNotEmpty ? _activeWidgets.first : 'gold_price';
            }
          });
          _saveDashboardConfig();
        }
      }
    });

    // 1. Fetch Gold Rate Stream
    _goldSub = _goldPriceService.getGlobalGoldPricesStream().listen((prices) {
      if (prices.isNotEmpty && mounted) {
        final latest = prices.first;
        final double rate22k = latest.price;
        setState(() {
          _latestGoldPrice = latest;
        });
        HomeWidgetService().updateGoldWidget(
          rate22k: rate22k,
          changeToday: latest.priceChange,
          city: _weatherCity,
        );
      }
    });

    // 2. Fetch Bank Accounts Stream
    _accountsSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('finance_accounts')
        .snapshots()
        .listen((snap) {
      double total = 0.0;
      final accs = snap.docs.map((d) {
        final data = d.data();
        total += (data['currentBalance'] as num? ?? data['balance'] as num? ?? 0.0).toDouble();
        return data;
      }).toList();

      if (mounted) {
        setState(() {
          _bankAccounts = accs;
          _totalBalance = total;
          _activeBankName = accs.length == 1
              ? (accs.first['name'] ?? 'Active Bank')
              : '${accs.length} Active Accounts';
        });
        HomeWidgetService().syncAllWidgets();
      }
    });

    // 3. Today's Transactions
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    double manualCred = 0.0;
    double manualDeb = 0.0;
    double smsCred = 0.0;
    double smsDeb = 0.0;

    _txSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('finance_transactions')
        .snapshots()
        .listen((snap) {
      double c = 0.0;
      double d = 0.0;
      for (final doc in snap.docs) {
        final data = doc.data();
        final date = data['date'];
        DateTime? dt;
        if (date is Timestamp) {
          dt = date.toDate();
        } else if (date is String) {
          dt = DateTime.tryParse(date);
        }

        final type = (data['type'] ?? '').toString().toLowerCase();
        if (dt != null && DateFormat('yyyy-MM-dd').format(dt) == todayStr) {
          final amt = (data['amount'] as num? ?? 0.0).toDouble();
          if (type == 'income' || type == 'credit' || type == 'received') {
            c += amt;
          } else if (type == 'expense' || type == 'debit' || type == 'sent') {
            d += amt;
          }
        }
      }
      manualCred = c;
      manualDeb = d;
      if (mounted) {
        setState(() {
          _todayCredited = manualCred + smsCred;
          _todayDebited = manualDeb + smsDeb;
        });
        HomeWidgetService().syncAllWidgets();
      }
    });

    _smsTxSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('sms_transactions')
        .snapshots()
        .listen((snap) {
      double c = 0.0;
      double d = 0.0;
      for (final doc in snap.docs) {
        final data = doc.data();
        DateTime? dt;
        final ts = data['timestamp'];
        if (ts is Timestamp) {
          dt = ts.toDate();
        } else if (ts is String) {
          dt = DateTime.tryParse(ts);
        } else if (ts is int) {
          dt = DateTime.fromMillisecondsSinceEpoch(ts);
        }

        final type = (data['type'] ?? '').toString().toLowerCase();
        final cat = (data['category'] ?? '').toString();
        if (cat.contains('Ignored') || cat == 'Self Transfer') continue;

        if (dt != null && DateFormat('yyyy-MM-dd').format(dt) == todayStr) {
          final amt = (data['amount'] as num? ?? 0.0).toDouble();
          if (type == 'credit' || type == 'income') {
            c += amt;
          } else if (type == 'debit' || type == 'expense') {
            d += amt;
          }
        }
      }
      smsCred = c;
      smsDeb = d;
      if (mounted) {
        setState(() {
          _todayCredited = manualCred + smsCred;
          _todayDebited = manualDeb + smsDeb;
        });
        HomeWidgetService().syncAllWidgets();
      }
    });

    // 4. Work Shift
    final now = DateTime.now();
    final currentRosterMonth = DateFormat('yyyy-MM').format(now);
    _shiftsSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('shifts')
        .doc(currentRosterMonth)
        .collection('daily_shifts')
        .doc(todayStr)
        .snapshots()
        .listen((snap) {
      if (mounted) {
        setState(() => _todayShift = snap.exists ? snap.data() : null);
        HomeWidgetService().syncAllWidgets();
      }
    });

    // 5. Tech Events & Walk-ins
    _eventsSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('events')
        .snapshots()
        .listen((snap) {
      int t = 0;
      for (var doc in snap.docs) {
        final d = doc.data();
        if (d['notInterested'] == true) continue;
        final dStr = (d['date'] ?? '').toString();
        if (dStr == todayStr) t++;
      }
      if (mounted) {
        setState(() => _todayEventsCount = t);
      }
    });

    _walkinsSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('walkins')
        .snapshots()
        .listen((snap) {
      int t = 0;
      for (var doc in snap.docs) {
        final d = doc.data();
        if (d['notInterested'] == true) continue;
        final dStr = (d['date'] ?? '').toString();
        if (dStr == todayStr) t++;
      }
      if (mounted) {
        setState(() => _todayWalkinsCount = t);
      }
    });

    // 6. Reminders, Daily Habits, Notes
    _remindersSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('calendar_reminders')
        .snapshots()
        .listen((snap) {
      final active = snap.docs.where((d) {
        final date = (d.data()['date'] ?? '').toString();
        final status = (d.data()['status'] ?? '').toString().toLowerCase();
        return date == todayStr && status != 'completed';
      }).length;
      if (mounted) setState(() => _todayRemindersCount = active);
    });

    _dailyRemindersSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('daily_reminders')
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _dailyRemindersCount = snap.docs.length);
    });

    _notesSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notes')
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _totalNotesCount = snap.docs.length);
    });
  }

  void _showCustomizeDashboardSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final sheetBg = isDark ? const Color(0xFF1E293B) : Colors.white;

          final allowedKeys = _widgetMetadata.keys.where(_isWidgetAllowed).toList();

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: sheetBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '✨ Customize Dashboard',
                      style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Pick your Featured Hero Card & drag/toggle cards to display below.',
                  style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                Text(
                  'FEATURED HERO CARD',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                    color: Colors.blueAccent,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: allowedKeys.map((wKey) {
                    final meta = _widgetMetadata[wKey]!;
                    final isHero = _heroWidget == wKey;
                    final col = meta['color'] as Color;
                    return ChoiceChip(
                      avatar: Icon(meta['icon'] as IconData, size: 14, color: isHero ? Colors.white : col),
                      label: Text(meta['title'] as String),
                      selected: isHero,
                      selectedColor: col.withValues(alpha: 0.8),
                      labelStyle: TextStyle(
                        color: isHero ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      onSelected: (selected) {
                        if (selected) {
                          setSheetState(() {
                            _heroWidget = wKey;
                            if (!_activeWidgets.contains(wKey)) {
                              _activeWidgets.insert(0, wKey);
                            }
                          });
                          setState(() {});
                          _saveDashboardConfig();
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'ENABLED CARDS (DRAG TO REORDER)',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                        color: isDark ? Colors.white60 : Colors.grey[700],
                      ),
                    ),
                    Text(
                      '${_activeWidgets.length} Active',
                      style: const TextStyle(fontSize: 11, color: Colors.blueAccent, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: allowedKeys.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, idx) {
                      final key = allowedKeys[idx];
                      final meta = _widgetMetadata[key]!;
                      final isSelected = _activeWidgets.contains(key);
                      final isHero = _heroWidget == key;
                      final Color col = meta['color'] as Color;

                      return SwitchListTile(
                        value: isSelected,
                        activeThumbColor: col,
                        secondary: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: col.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(meta['icon'] as IconData, color: col, size: 18),
                        ),
                        title: Row(
                          children: [
                            Text(meta['title'] as String, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                            if (isHero) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('HERO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                              ),
                            ],
                          ],
                        ),
                        onChanged: (val) {
                          setSheetState(() {
                            if (val) {
                              _activeWidgets.add(key);
                            } else {
                              if (_activeWidgets.length > 1) {
                                _activeWidgets.remove(key);
                                if (_heroWidget == key) {
                                  _heroWidget = _activeWidgets.first;
                                }
                              }
                            }
                          });
                          setState(() {});
                          _saveDashboardConfig();
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0B0F19) : const Color(0xFFF8FAFC);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bgColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Filter secondary widgets (whatever is chosen as Hero card is NOT duplicated below)
    final secondaryWidgets = _activeWidgets.where((w) => w != _heroWidget).toList();

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // 1. Dynamic Ambient Context Header Ribbon
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: _buildAmbientContextRibbon(isDark),
              ),
            ),

            // 2. Primary Hero Bento Card (Wide 2-Span, Long-Press & Draggable to Swap)
            if (_isWidgetAllowed(_heroWidget))
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: _buildDraggableHeroCard(_heroWidget, isDark),
                ),
              ),

            // 3. Dynamic Secondary Bento Grid (2-Column Flow with Long-Press Drag-and-Drop)
            if (secondaryWidgets.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    mainAxisExtent: 148,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final widgetType = secondaryWidgets[index];
                      return _buildDraggableCompactCard(widgetType, isDark);
                    },
                    childCount: secondaryWidgets.length,
                  ),
                ),
              )
            else
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCustomizeDashboardSheet,
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
          side: BorderSide(
            color: isDark ? Colors.white24 : Colors.black12,
            width: 1,
          ),
        ),
        icon: const Icon(Icons.dashboard_customize_rounded, size: 18, color: Colors.blueAccent),
        label: Text(
          'Customize',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ),
    );
  }

  // ==========================================
  // 🌟 DRAGGABLE & REORDERABLE CARD WRAPPERS
  // ==========================================
  Widget _buildDraggableHeroCard(String widgetKey, bool isDark) {
    final meta = _widgetMetadata[widgetKey] ?? _widgetMetadata['gold_price']!;
    final title = meta['title'] as String;
    final color = meta['color'] as Color;
    final icon = meta['icon'] as IconData;

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != widgetKey,
      onAcceptWithDetails: (details) {
        _swapCards(details.data, widgetKey);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty;
        return AnimatedScale(
          scale: isHovered ? 1.02 : 1.0,
          duration: const Duration(milliseconds: 180),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: isHovered
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: color, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.35),
                        blurRadius: 14,
                        spreadRadius: 2,
                      ),
                    ],
                  )
                : null,
            child: LongPressDraggable<String>(
              data: widgetKey,
              delay: const Duration(milliseconds: 300),
              hapticFeedbackOnStart: true,
              feedback: Material(
                color: Colors.transparent,
                child: SizedBox(
                  width: MediaQuery.of(context).size.width - 32,
                  height: 130,
                  child: Opacity(
                    opacity: 0.9,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.45),
                            blurRadius: 20,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(icon, color: color, size: 28),
                          const SizedBox(width: 12),
                          Text(
                            title,
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const Spacer(),
                          const Icon(Icons.drag_indicator_rounded, color: Colors.blueAccent, size: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.35,
                child: _buildHeroBentoCard(widgetKey, isDark),
              ),
              child: _buildHeroBentoCard(widgetKey, isDark),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDraggableCompactCard(String widgetKey, bool isDark) {
    final meta = _widgetMetadata[widgetKey] ?? _widgetMetadata['gold_price']!;
    final title = meta['title'] as String;
    final color = meta['color'] as Color;
    final icon = meta['icon'] as IconData;

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != widgetKey,
      onAcceptWithDetails: (details) {
        _swapCards(details.data, widgetKey);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty;
        return AnimatedScale(
          scale: isHovered ? 1.04 : 1.0,
          duration: const Duration(milliseconds: 180),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: isHovered
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: color, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.35),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  )
                : null,
            child: LongPressDraggable<String>(
              data: widgetKey,
              delay: const Duration(milliseconds: 300),
              hapticFeedbackOnStart: true,
              feedback: Material(
                color: Colors.transparent,
                child: SizedBox(
                  width: 160,
                  height: 140,
                  child: Opacity(
                    opacity: 0.9,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: color, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.45),
                            blurRadius: 18,
                            spreadRadius: 3,
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, color: color, size: 28),
                          const SizedBox(height: 8),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.3,
                child: _buildCompactBentoCard(widgetKey, isDark),
              ),
              child: _buildCompactBentoCard(widgetKey, isDark),
            ),
          ),
        );
      },
    );
  }

  // ==========================================
  // 🌟 1. Dynamic Ambient Context Ribbon
  // ==========================================
  Widget _buildAmbientContextRibbon(bool isDark) {
    final user = FirebaseAuth.instance.currentUser;
    String rawName = user?.displayName ?? '';
    if (rawName.trim().isEmpty && user?.email != null) {
      rawName = user!.email!.split('@').first;
    }
    String cleanName = rawName.split(' ').first;
    if (cleanName.isNotEmpty) {
      cleanName = cleanName[0].toUpperCase() + (cleanName.length > 1 ? cleanName.substring(1) : '');
    } else {
      cleanName = 'Friend';
    }

    final hour = DateTime.now().hour;
    String greeting = 'Good Morning';
    String emoji = '👋';
    if (hour >= 12 && hour < 17) { greeting = 'Good Afternoon'; emoji = '☀️'; }
    else if (hour >= 17 && hour < 21) { greeting = 'Good Evening'; emoji = '🌆'; }
    else if (hour >= 21 || hour < 5) { greeting = 'Good Night'; emoji = '🌙'; }

    final dateStr = DateFormat('EEEE, d MMMM').format(DateTime.now());

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131C2E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left side: Single-line greeting + date with icon
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '$greeting, $cleanName $emoji',
                        style: GoogleFonts.outfit(
                          fontSize: 17.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 12,
                      color: isDark ? Colors.white54 : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      dateStr,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Right side: Compact, polished Weather Widget Chip
          Tooltip(
            message: '$_weatherCondition in $_weatherCity (Tap to refresh)',
            child: InkWell(
              onTap: () => _fetchWeather(force: true),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.blue.shade50.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? Colors.blueAccent.withValues(alpha: 0.3) : Colors.blue.shade100,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_weatherIcon, color: Colors.blueAccent, size: 20),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _weatherTemp,
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          _weatherCity,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white60 : Colors.blueGrey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 🌟 2. Dedicated Featured Hero Bento Cards (For ALL Categories)
  // ==========================================
  Widget _buildHeroBentoCard(String widgetKey, bool isDark) {
    final meta = _widgetMetadata[widgetKey] ?? _widgetMetadata['gold_price']!;
    final glowColor = meta['color'] as Color;

    Widget content;
    switch (widgetKey) {
      case 'gold_price':
        content = _buildHeroGoldContent(isDark);
        break;
      case 'bank_accounts':
        content = _buildHeroBankAccountsContent(isDark);
        break;
      case 'expenses':
        content = _buildHeroExpensesContent(isDark);
        break;
      case 'shifts':
        content = _buildHeroShiftContent(isDark);
        break;
      case 'events_walkins':
        content = _buildHeroEventsWalkinsContent(isDark);
        break;
      case 'reminders':
        content = _buildHeroRemindersContent(isDark);
        break;
      case 'daily_reminders':
        content = _buildHeroDailyRemindersContent(isDark);
        break;
      case 'notes':
        content = _buildHeroNotesContent(isDark);
        break;
      case 'voice_assistant':
        content = _buildHeroVoiceAssistantContent(isDark);
        break;
      default:
        content = _buildHeroGoldContent(isDark);
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131C2E) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: glowColor.withValues(alpha: 0.45),
          width: 1.8,
        ),
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: isDark ? 0.16 : 0.08),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            if (widget.onNavigateToFeature != null) {
              widget.onNavigateToFeature!(widgetKey);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: content,
          ),
        ),
      ),
    );
  }

  // 1. Gold Hero (22K Standard Only, No 24K)
  Widget _buildHeroGoldContent(bool isDark) {
    final price22k = _latestGoldPrice?.price ?? 7200.0;
    final sovereign = price22k * 8; // 1 Pavan (8g 22K)
    final changeVal = _latestGoldPrice?.priceChange ?? 25.0;
    final isPos = changeVal >= 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.monetization_on_rounded, color: Colors.amber, size: 18),
                ),
                const SizedBox(width: 8),
                Text(
                  'Live Gold Rate (22K Standard)',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isPos
                    ? const Color(0xFF10B981).withValues(alpha: 0.15)
                    : const Color(0xFFF43F5E).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    isPos ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                    color: isPos ? const Color(0xFF10B981) : const Color(0xFFF43F5E),
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${isPos ? "+" : ""}₹${changeVal.abs().toStringAsFixed(0)} Today',
                    style: TextStyle(
                      color: isPos ? const Color(0xFF10B981) : const Color(0xFFF43F5E),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Big 22K Display
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '₹${NumberFormat('#,##,##0').format(price22k)}',
              style: GoogleFonts.outfit(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: Colors.amber,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              '/ gram (22K)',
              style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 8g Sovereign (Pavan) calculation for 22K
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.workspace_premium_rounded, color: Colors.amber, size: 16),
                  SizedBox(width: 6),
                  Text('8g Sovereign (1 Pavan • 22K)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                ],
              ),
              Text(
                '₹${NumberFormat('#,##,##0').format(sovereign)}',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.amber),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 2. Bank Accounts Breakdown Hero (All Registered Banks & Balances)
  Widget _buildHeroBankAccountsContent(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.lightBlueAccent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.account_balance_rounded, color: Colors.lightBlueAccent, size: 18),
                ),
                const SizedBox(width: 8),
                Text(
                  'Bank Balances (${_bankAccounts.length} Connected)',
                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            Text(
              'Total: ₹${NumberFormat('#,##,##0').format(_totalBalance)}',
              style: const TextStyle(fontSize: 12, color: Colors.lightBlueAccent, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_bankAccounts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No bank accounts configured yet. Tap to connect accounts.', style: TextStyle(color: Colors.grey, fontSize: 13)),
          )
        else
          Column(
            children: _bankAccounts.take(4).map((acc) {
              final name = (acc['name'] ?? 'Bank Account').toString();
              final bal = (acc['currentBalance'] as num? ?? acc['balance'] as num? ?? 0.0).toDouble();
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '₹${NumberFormat('#,##,##0.00').format(bal)}',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.lightBlueAccent,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  // 3. Cumulative Balance & Daily Cashflow Hero
  Widget _buildHeroExpensesContent(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF43F5E).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.swap_vert_rounded, color: Color(0xFFF43F5E), size: 18),
                ),
                const SizedBox(width: 8),
                Text(
                  'Cumulative Balance & Cashflow',
                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Text('Live Flow', style: TextStyle(fontSize: 11, color: Color(0xFFF43F5E), fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '₹${NumberFormat('#,##,##0.00').format(_totalBalance)}',
          style: GoogleFonts.outfit(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Today\'s Inflow', style: TextStyle(fontSize: 10, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                      '+₹${NumberFormat('#,##,##0').format(_todayCredited)}',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14, color: const Color(0xFF10B981)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF43F5E).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Today\'s Outflow', style: TextStyle(fontSize: 10, color: Color(0xFFF43F5E), fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                      '-₹${NumberFormat('#,##,##0').format(_todayDebited)}',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14, color: const Color(0xFFF43F5E)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 4. Shift Hero
  Widget _buildHeroShiftContent(bool isDark) {
    String title = 'NO SHIFT TODAY';
    String timing = 'Off Duty • Enjoy your day';
    Color color = Colors.cyan;

    if (_todayShift != null) {
      final raw = (_todayShift!['shift_type'] ?? _todayShift!['shiftType'] ?? '').toString().toLowerCase();
      if (!raw.contains('off')) {
        title = '${raw.toUpperCase().replaceAll('_', ' ')} SHIFT';
        color = Colors.purpleAccent;
        final start = (_todayShift!['start_time'] ?? _todayShift!['startTime'] ?? '').toString();
        final end = (_todayShift!['end_time'] ?? _todayShift!['endTime'] ?? '').toString();
        if (start.isNotEmpty && end.isNotEmpty) timing = '$start - $end';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.work_history_rounded, color: color, size: 18),
                ),
                const SizedBox(width: 8),
                Text('Today\'s Work Schedule', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            Text('Today', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          title,
          style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w900, color: color),
        ),
        const SizedBox(height: 4),
        Text(timing, style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.grey[700])),
      ],
    );
  }

  // 5. Events & Walk-ins Hero
  Widget _buildHeroEventsWalkinsContent(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.tealAccent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.rocket_launch_rounded, color: Colors.tealAccent, size: 18),
                ),
                const SizedBox(width: 8),
                Text('Tech Events & Walk-In Drives', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const Text('Hiring & Meetups', style: TextStyle(fontSize: 11, color: Colors.tealAccent, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Tech Events', style: TextStyle(fontSize: 11, color: Colors.teal, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('$_todayEventsCount Today', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.teal)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Walk-Ins', style: TextStyle(fontSize: 11, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('$_todayWalkinsCount Today', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.blueAccent)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 6. Calendar Reminders Hero
  Widget _buildHeroRemindersContent(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.indigoAccent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.calendar_month_rounded, color: Colors.indigoAccent, size: 18),
                ),
                const SizedBox(width: 8),
                Text('Today\'s Calendar Tasks', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            Text('$_todayRemindersCount Due', style: const TextStyle(fontSize: 11, color: Colors.indigoAccent, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '$_todayRemindersCount Tasks Scheduled',
          style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.indigoAccent),
        ),
        const SizedBox(height: 4),
        Text('Tap to open Calendar & Agenda', style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.grey[700])),
      ],
    );
  }

  // 7. Daily Habits Hero
  Widget _buildHeroDailyRemindersContent(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.orangeAccent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.alarm_on_rounded, color: Colors.orangeAccent, size: 18),
                ),
                const SizedBox(width: 8),
                Text('Daily Habits & Routines', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            Text('$_dailyRemindersCount Active', style: const TextStyle(fontSize: 11, color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '$_dailyRemindersCount Habit Check-ins Active',
          style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.orangeAccent),
        ),
        const SizedBox(height: 4),
        Text('Manage daily alarms, hydration & medicine alerts', style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.grey[700])),
      ],
    );
  }

  // 8. Notes Hero
  Widget _buildHeroNotesContent(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.note_alt_rounded, color: Colors.cyanAccent, size: 18),
                ),
                const SizedBox(width: 8),
                Text('Quick Notes & Workspace', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            Text('$_totalNotesCount Notes', style: const TextStyle(fontSize: 11, color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '$_totalNotesCount Personal Drafts & Notes',
          style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.cyanAccent),
        ),
        const SizedBox(height: 4),
        Text('Tap to write or review pinned notes', style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.grey[700])),
      ],
    );
  }

  // 9. Voice Assistant Hero
  Widget _buildHeroVoiceAssistantContent(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.mic_rounded, color: Colors.redAccent, size: 18),
                ),
                const SizedBox(width: 8),
                Text('Ask Buddy (AI Voice Assistant)', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const Text('AI Ready', style: TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFEF4444), Color(0xFFDC2626)]),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mic, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Tap to speak with Buddy...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // 🌟 3. Compact Bento Cards (With Glowing Themed Borders)
  // ==========================================
  Widget _buildCompactBentoCard(String type, bool isDark) {
    final meta = _widgetMetadata[type] ?? _widgetMetadata['gold_price']!;
    final Color col = meta['color'] as Color;
    final IconData icon = meta['icon'] as IconData;
    final String title = meta['title'] as String;

    Widget body;
    switch (type) {
      case 'gold_price':
        final price = _latestGoldPrice?.price ?? 7200.0;
        body = Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('₹${price.toStringAsFixed(0)}',
                  style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.w900, color: Colors.amber)),
              const SizedBox(height: 2),
              Text('22K / 1 gram', style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white60 : Colors.grey[600])),
            ],
          ),
        );
        break;
      case 'bank_accounts':
        body = Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('₹${NumberFormat('#,##,##0').format(_totalBalance)}',
                  style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.lightBlueAccent)),
              const SizedBox(height: 2),
              Text(_activeBankName, style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white60 : Colors.grey[600]), maxLines: 1),
            ],
          ),
        );
        break;
      case 'expenses':
        body = Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '+₹${NumberFormat('#,##,##0').format(_todayCredited)}',
                    style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF10B981)),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '-₹${NumberFormat('#,##,##0').format(_todayDebited)}',
                    style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFFF43F5E)),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text('Today Inflow • Outflow', style: TextStyle(fontSize: 10, color: isDark ? Colors.white60 : Colors.grey[600])),
            ],
          ),
        );
        break;
      case 'shifts':
        String shiftTitle = 'Week Off 🏖️';
        String shiftTime = 'Tap for roster';
        if (_todayShift != null) {
          final raw = (_todayShift!['shift_type'] ?? _todayShift!['shiftType'] ?? '').toString().toLowerCase();
          if (!raw.contains('off') && raw.isNotEmpty) {
            shiftTitle = '${raw.toUpperCase().replaceAll('_', ' ')} SHIFT';
            final start = (_todayShift!['start_time'] ?? _todayShift!['startTime'] ?? '').toString();
            final end = (_todayShift!['end_time'] ?? _todayShift!['endTime'] ?? '').toString();
            if (start.isNotEmpty && end.isNotEmpty) {
              shiftTime = '$start - $end';
            } else {
              shiftTime = 'On Duty Today';
            }
          }
        }
        body = Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                shiftTitle,
                style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.purpleAccent),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                shiftTime,
                style: TextStyle(fontSize: 10, color: isDark ? Colors.white60 : Colors.grey[600]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
        break;
      case 'events_walkins':
        body = Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('$_todayEventsCount Events • $_todayWalkinsCount Drives',
                  style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.bold, color: Colors.tealAccent)),
              const SizedBox(height: 2),
              Text('Active Opportunities Today', style: TextStyle(fontSize: 10, color: isDark ? Colors.white60 : Colors.grey[600])),
            ],
          ),
        );
        break;
      case 'reminders':
        body = Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('$_todayRemindersCount Due',
                  style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.indigoAccent)),
              const SizedBox(height: 2),
              Text('Scheduled Tasks', style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white60 : Colors.grey[600])),
            ],
          ),
        );
        break;
      case 'daily_reminders':
        body = Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('$_dailyRemindersCount Habits',
                  style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
              const SizedBox(height: 2),
              Text('Daily Check-ins Active', style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white60 : Colors.grey[600])),
            ],
          ),
        );
        break;
      case 'notes':
        body = Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('$_totalNotesCount Notes',
                  style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
              const SizedBox(height: 2),
              Text('Pinned & Drafts', style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white60 : Colors.grey[600])),
            ],
          ),
        );
        break;
      case 'voice_assistant':
        body = Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFEF4444), Color(0xFFDC2626)]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.mic, color: Colors.white, size: 14),
                const SizedBox(width: 4),
                Text('Ask Buddy', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5)),
              ],
            ),
          ),
        );
        break;
      default:
        body = const Center(child: Text('Tap to open'));
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131C2E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: col.withValues(alpha: isDark ? 0.35 : 0.22),
          width: 1.3,
        ),
        boxShadow: [
          BoxShadow(
            color: col.withValues(alpha: isDark ? 0.12 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            if (widget.onNavigateToFeature != null) {
              widget.onNavigateToFeature!(type);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5.5),
                      decoration: BoxDecoration(
                        color: col.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, color: col, size: 14),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white.withValues(alpha: 0.85) : const Color(0xFF334155),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, size: 10, color: isDark ? Colors.white30 : Colors.black26),
                  ],
                ),
                Expanded(
                  child: Center(child: body),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
