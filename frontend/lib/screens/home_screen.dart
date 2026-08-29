import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../services/gold_price_service.dart';
import '../services/home_widget_service.dart';
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
  
  // Custom dashboard widget list chosen by user
  List<String> _activeWidgets = ['gold_price', 'bank_accounts', 'expenses', 'shifts', 'weather', 'voice_assistant'];
  String _heroWidget = 'gold_price'; // Default hero card

  bool _isLoading = true;

  // Live Data State
  GoldPrice? _latestGoldPrice;
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

  // Weather state
  String _weatherTemp = '--°C';
  String _weatherCity = 'Chennai';
  String _weatherCondition = 'Partly Cloudy';
  IconData _weatherIcon = Icons.wb_sunny_rounded;

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

  final Map<String, Map<String, dynamic>> _widgetMetadata = {
    'gold_price': {
      'title': 'Gold Rates (24K & 22K)',
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
      'title': 'Today\'s Cashflow',
      'module': 'finance',
      'icon': Icons.swap_vert_rounded,
      'color': const Color(0xFFF43F5E),
    },
    'shifts': {
      'title': 'Work Duty & Shift',
      'module': 'shifts',
      'icon': Icons.work_history_rounded,
      'color': Colors.purpleAccent,
    },
    'events_walkins': {
      'title': 'Tech & Walk-Ins',
      'module': 'events',
      'icon': Icons.rocket_launch_rounded,
      'color': Colors.tealAccent,
    },
    'reminders': {
      'title': 'Calendar Tasks',
      'module': 'reminders',
      'icon': Icons.calendar_month_rounded,
      'color': Colors.indigoAccent,
    },
    'daily_reminders': {
      'title': 'Daily Habit Check-ins',
      'module': 'daily_reminders',
      'icon': Icons.alarm_on_rounded,
      'color': Colors.orangeAccent,
    },
    'notes': {
      'title': 'Quick Notes',
      'module': 'notes',
      'icon': Icons.note_alt_rounded,
      'color': Colors.cyanAccent,
    },
    'weather': {
      'title': 'Atmospheric Weather',
      'module': 'all',
      'icon': Icons.wb_sunny_rounded,
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
  }

  @override
  void dispose() {
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

    if (cachedModules != null && cachedModules.isNotEmpty) {
      _enabledModules = cachedModules;
    }

    if (savedWidgets != null && savedWidgets.isNotEmpty) {
      _activeWidgets = savedWidgets;
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

  Future<void> _fetchWeather() async {
    try {
      final response = await http
          .get(Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=13.0827&longitude=80.2707&current_weather=true'))
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

        if (mounted) {
          setState(() {
            _weatherCity = 'Chennai';
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
            // Clean up active widgets if module was revoked
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
        final double rate24k = rate22k > 0 ? (rate22k / 22 * 24) : 0.0;
        setState(() {
          _latestGoldPrice = latest;
        });
        HomeWidgetService().updateGoldWidget(
          rate24k: rate24k,
          rate22k: rate22k,
          changeToday: latest.priceChange,
          city: 'Chennai',
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
          _totalBalance = total;
          _activeBankName = accs.length == 1
              ? (accs.first['name'] ?? 'Active Bank')
              : '${accs.length} Active Accounts';
        });
        HomeWidgetService().updateFinanceWidget(
          totalBalance: _totalBalance,
          todayIn: _todayCredited,
          todayOut: _todayDebited,
          bankName: _activeBankName,
        );
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
                  'Select which modules appear on your home screen and pick your Primary Hero Card.',
                  style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.grey[600]),
                ),
                const SizedBox(height: 18),
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
                  children: _activeWidgets.map((wKey) {
                    final meta = _widgetMetadata[wKey]!;
                    final isHero = _heroWidget == wKey;
                    return ChoiceChip(
                      label: Text(meta['title'] as String),
                      selected: isHero,
                      selectedColor: Colors.blueAccent.withValues(alpha: 0.25),
                      onSelected: (selected) {
                        if (selected) {
                          setSheetState(() => _heroWidget = wKey);
                          setState(() => _heroWidget = wKey);
                          _saveDashboardConfig();
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),
                Text(
                  'ENABLED MODULE CARDS',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                    color: isDark ? Colors.white60 : Colors.grey[700],
                  ),
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
                        title: Text(meta['title'] as String, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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

    // Filter secondary widgets (all active except the hero)
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

            // 2. Primary Hero Bento Card (Wide 2-Span)
            if (_activeWidgets.contains(_heroWidget))
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: _buildHeroBentoCard(_heroWidget, isDark),
                ),
              ),

            // 3. Dynamic Secondary Bento Grid (2-Column Flow)
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
                      return _buildCompactBentoCard(widgetType, isDark);
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

    final dateStr = DateFormat('EEE, d MMMM').format(DateTime.now());

    return Container(
      padding: const EdgeInsets.all(14),
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
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting, $cleanName $emoji',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateStr,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // Weather Status Pill
          InkWell(
            onTap: _fetchWeather,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(_weatherIcon, color: Colors.blueAccent, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    _weatherTemp,
                    style: GoogleFonts.outfit(
                      color: Colors.blueAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 🌟 2. Featured Hero Bento Card (Wide 2-Span)
  // ==========================================
  Widget _buildHeroBentoCard(String widgetKey, bool isDark) {
    Widget content;
    Color glowColor;

    switch (widgetKey) {
      case 'gold_price':
        content = _buildHeroGoldContent(isDark);
        glowColor = Colors.amber;
        break;
      case 'bank_accounts':
      case 'expenses':
        content = _buildHeroFinanceContent(isDark);
        glowColor = Colors.lightBlueAccent;
        break;
      case 'shifts':
        content = _buildHeroShiftContent(isDark);
        glowColor = Colors.purpleAccent;
        break;
      default:
        content = _buildHeroGoldContent(isDark);
        glowColor = Colors.amber;
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131C2E) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: glowColor.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: isDark ? 0.12 : 0.06),
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

  Widget _buildHeroGoldContent(bool isDark) {
    final price22k = _latestGoldPrice?.price ?? 7200.0;
    final price24k = price22k > 0 ? (price22k / 22 * 24) : 7850.0;
    final sovereign = price22k * 8; // 1 Pavan (8g)
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
                  'Live Gold Market Rates',
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
        // Big Price Display Row
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('24K Pure Gold (1g)', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '₹${price24k.toStringAsFixed(0)}',
                    style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.amber,
                    ),
                  ),
                ],
              ),
            ),
            Container(width: 1, height: 36, color: isDark ? Colors.white12 : Colors.black12),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('22K Standard (1g)', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '₹${price22k.toStringAsFixed(0)}',
                    style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Sovereign (8g) Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('8g Sovereign (Pavan)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              Text(
                '₹${NumberFormat('#,##,##0').format(sovereign)}',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.amber),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeroFinanceContent(bool isDark) {
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
                  'Total Net Bank Balance',
                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            Text(
              _activeBankName,
              style: const TextStyle(fontSize: 11, color: Colors.lightBlueAccent, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '₹${NumberFormat('#,##,##0.00').format(_totalBalance)}',
          style: GoogleFonts.outfit(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: Colors.lightBlueAccent,
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

  // ==========================================
  // 🌟 3. Compact Bento Cards (2-Column Grid)
  // ==========================================
  Widget _buildCompactBentoCard(String type, bool isDark) {
    final meta = _widgetMetadata[type]!;
    final Color col = meta['color'] as Color;
    final IconData icon = meta['icon'] as IconData;
    final String title = meta['title'] as String;

    Widget body;
    switch (type) {
      case 'gold_price':
        final price = _latestGoldPrice?.price ?? 7200.0;
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('₹${price.toStringAsFixed(0)}',
                style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.w900, color: Colors.amber)),
            const SizedBox(height: 2),
            Text('22K / 1 gram', style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white60 : Colors.grey[600])),
          ],
        );
        break;
      case 'bank_accounts':
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('₹${NumberFormat('#,##,##0').format(_totalBalance)}',
                style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.lightBlueAccent)),
            const SizedBox(height: 2),
            Text(_activeBankName, style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white60 : Colors.grey[600]), maxLines: 1),
          ],
        );
        break;
      case 'expenses':
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('-₹${NumberFormat('#,##,##0').format(_todayDebited)}',
                style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w900, color: const Color(0xFFF43F5E))),
            const SizedBox(height: 2),
            Text('+₹${NumberFormat('#,##,##0').format(_todayCredited)} Inflow',
                style: const TextStyle(fontSize: 10.5, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
          ],
        );
        break;
      case 'shifts':
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _todayShift != null ? 'Active Shift' : 'Week Off 🏖️',
              style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.purpleAccent),
            ),
            const SizedBox(height: 2),
            Text('Tap to check calendar', style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white60 : Colors.grey[600])),
          ],
        );
        break;
      case 'events_walkins':
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$_todayEventsCount Events',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.tealAccent)),
            const SizedBox(height: 2),
            Text('$_todayWalkinsCount Walk-Ins Today', style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white60 : Colors.grey[600])),
          ],
        );
        break;
      case 'reminders':
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$_todayRemindersCount Due',
                style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.indigoAccent)),
            const SizedBox(height: 2),
            Text('Scheduled Tasks', style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white60 : Colors.grey[600])),
          ],
        );
        break;
      case 'daily_reminders':
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$_dailyRemindersCount Habits',
                style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
            const SizedBox(height: 2),
            Text('Daily Check-ins Active', style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white60 : Colors.grey[600])),
          ],
        );
        break;
      case 'notes':
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$_totalNotesCount Notes',
                style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
            const SizedBox(height: 2),
            Text('Pinned & Drafts', style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white60 : Colors.grey[600])),
          ],
        );
        break;
      case 'weather':
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$_weatherCity • $_weatherTemp',
                style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
            const SizedBox(height: 2),
            Text(_weatherCondition, style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white60 : Colors.grey[600])),
          ],
        );
        break;
      case 'voice_assistant':
        body = Container(
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
        );
        break;
      default:
        body = const Text('Tap to open');
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131C2E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 8,
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: col.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, color: col, size: 15),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, size: 11, color: isDark ? Colors.white30 : Colors.black26),
                  ],
                ),
                body,
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white54 : Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
