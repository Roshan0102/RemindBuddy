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
import '../models/gold_price.dart';

class HomeScreen extends StatefulWidget {
  final Function(String featureId)? onNavigateToFeature;

  const HomeScreen({super.key, this.onNavigateToFeature});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GoldPriceService _goldPriceService = GoldPriceService();

  // 8 Grid Slot widget IDs saved in SharedPreferences
  List<String?> _slotWidgets = List.filled(8, null);
  bool _isLoadingSlots = true;

  // Live Data State
  GoldPrice? _latestGoldPrice;
  List<Map<String, dynamic>> _bankAccounts = [];
  double _todayCredited = 0.0;
  double _todayDebited = 0.0;
  Map<String, dynamic>? _todayShift;
  int _upcomingEventsCount = 0;
  int _upcomingWalkinsCount = 0;
  int _todayRemindersCount = 0;
  int _totalNotesCount = 0;
  int _dailyRemindersCount = 0;

  // Weather State
  String _weatherTemp = '28°C';
  String _weatherCondition = 'Sunny';
  IconData _weatherIcon = Icons.wb_sunny_rounded;

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

  final Map<String, String> _availableWidgetTypes = {
    'gold_price': '🪙 Gold Rate (22K)',
    'bank_accounts': '🏦 Bank Balances',
    'expenses': '💳 Today\'s Cashflow',
    'shifts': '💼 Today\'s Shift',
    'events_walkins': '🚀 Tech & Walk-Ins',
    'voice_assistant': '🎙️ Voice Assistant (Ask Buddy)',
    'weather': '🌤️ Live Weather',
    'reminders': '📅 Calendar Reminders',
    'daily_reminders': '🔔 Daily Habits & Alerts',
    'notes': '📝 Quick Notes Summary',
  };

  @override
  void initState() {
    super.initState();
    _loadSlots();
    _loadDashboardData();
    _fetchWeather();
  }

  @override
  void dispose() {
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

  Future<void> _loadSlots() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSlots = prefs.getStringList('home_dashboard_slots');

    if (savedSlots != null && savedSlots.length == 8) {
      setState(() {
        _slotWidgets = savedSlots.map((s) => s.isEmpty ? null : s).toList();
        _isLoadingSlots = false;
      });
    } else {
      // Default pre-populated preset
      setState(() {
        _slotWidgets = [
          'gold_price',
          'bank_accounts',
          'expenses',
          'shifts',
          'events_walkins',
          'voice_assistant',
          'reminders',
          'notes',
        ];
        _isLoadingSlots = false;
      });
      _saveSlots();
    }
  }

  Future<void> _saveSlots() async {
    final prefs = await SharedPreferences.getInstance();
    final listToSave = _slotWidgets.map((s) => s ?? '').toList();
    await prefs.setStringList('home_dashboard_slots', listToSave);
  }

  Future<void> _fetchWeather() async {
    try {
      final res = await http
          .get(Uri.parse(
              'https://api.open-meteo.com/v1/forecast?latitude=13.0827&longitude=80.2707&current=temperature_2m,weather_code&timezone=auto'))
          .timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final current = data['current'];
        final temp = (current['temperature_2m'] as num?)?.round() ?? 28;
        final code = (current['weather_code'] as num?)?.toInt() ?? 0;

        String condition = 'Sunny';
        IconData icon = Icons.wb_sunny_rounded;

        if (code == 0) {
          condition = 'Clear Sky';
          icon = Icons.wb_sunny_rounded;
        } else if (code >= 1 && code <= 3) {
          condition = 'Partly Cloudy';
          icon = Icons.cloud_queue_rounded;
        } else if (code >= 45 && code <= 48) {
          condition = 'Foggy';
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
            _weatherTemp = '$temp°C';
            _weatherCondition = condition;
            _weatherIcon = icon;
          });
        }
      }
    } catch (_) {
      // Graceful fallback
    }
  }

  void _loadDashboardData() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // 1. Fetch Gold Rate Stream (22K)
    _goldSub = _goldPriceService.getGlobalGoldPricesStream().listen((prices) {
      if (prices.isNotEmpty && mounted) {
        setState(() => _latestGoldPrice = prices.first);
      }
    });

    // 2. Fetch Bank Accounts Stream from 'finance_accounts'
    _accountsSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('finance_accounts')
        .snapshots()
        .listen((snap) {
      if (mounted) {
        setState(() {
          _bankAccounts = snap.docs.map((d) => d.data()).toList();
        });
      }
    });

    // 3. Fetch Today's Credited and Debited Amounts
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    double manualCredited = 0.0;
    double manualDebited = 0.0;
    double smsCredited = 0.0;
    double smsDebited = 0.0;

    _txSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('finance_transactions')
        .snapshots()
        .listen((snap) {
      double cred = 0.0;
      double deb = 0.0;
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
        if (dt != null) {
          final dtStr = DateFormat('yyyy-MM-dd').format(dt);
          if (dtStr == todayStr) {
            final amt = (data['amount'] as num? ?? 0.0).toDouble();
            if (type == 'income' || type == 'credit' || type == 'received') {
              cred += amt;
            } else if (type == 'expense' || type == 'debit' || type == 'sent') {
              deb += amt;
            }
          }
        }
      }
      manualCredited = cred;
      manualDebited = deb;
      if (mounted) {
        setState(() {
          _todayCredited = manualCredited + smsCredited;
          _todayDebited = manualDebited + smsDebited;
        });
      }
    });

    _smsTxSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('sms_transactions')
        .snapshots()
        .listen((snap) {
      double cred = 0.0;
      double deb = 0.0;
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
        if (cat == 'Ignored' || cat == 'Ignored / Not Needed' || cat == 'Self Transfer') continue;

        if (dt != null) {
          final dtStr = DateFormat('yyyy-MM-dd').format(dt);
          if (dtStr == todayStr) {
            final amt = (data['amount'] as num? ?? 0.0).toDouble();
            if (type == 'credit' || type == 'income') {
              cred += amt;
            } else if (type == 'debit' || type == 'expense') {
              deb += amt;
            }
          }
        }
      }
      smsCredited = cred;
      smsDebited = deb;
      if (mounted) {
        setState(() {
          _todayCredited = manualCredited + smsCredited;
          _todayDebited = manualDebited + smsDebited;
        });
      }
    });

    // 4. Fetch Today's Work Shift
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
        setState(() {
          _todayShift = snap.exists ? snap.data() : null;
        });
      }
    });

    // 5. Fetch Tech Events & Walk-Ins
    _eventsSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('events')
        .snapshots()
        .listen((snap) {
      final nowStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final active = snap.docs.where((d) {
        final data = d.data();
        return (data['notInterested'] != true) &&
            ((data['date'] ?? '').toString().compareTo(nowStr) >= 0);
      }).length;
      if (mounted) setState(() => _upcomingEventsCount = active);
    });

    _walkinsSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('walkins')
        .snapshots()
        .listen((snap) {
      final nowStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final active = snap.docs.where((d) {
        final data = d.data();
        return (data['notInterested'] != true) &&
            ((data['date'] ?? '').toString().compareTo(nowStr) >= 0);
      }).length;
      if (mounted) setState(() => _upcomingWalkinsCount = active);
    });

    // 6. Fetch Today's Calendar Reminders
    _remindersSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('calendar_reminders')
        .snapshots()
        .listen((snap) {
      final activeToday = snap.docs.where((d) {
        final data = d.data();
        final date = (data['date'] ?? '').toString();
        final status = (data['status'] ?? '').toString().toLowerCase();
        return date == todayStr && status != 'completed';
      }).length;
      if (mounted) setState(() => _todayRemindersCount = activeToday);
    });

    // 7. Fetch Notes Count
    _notesSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notes')
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _totalNotesCount = snap.docs.length);
    });

    // 8. Fetch Daily Reminders Count
    _dailyRemindersSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('daily_reminders')
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _dailyRemindersCount = snap.docs.length);
    });
  }

  void _showAddWidgetSheet(int slotIndex) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final usedTypes = _slotWidgets.whereType<String>().toSet();
        final availableEntries = _availableWidgetTypes.entries
            .where((entry) => !usedTypes.contains(entry.key))
            .toList();

        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Select Widget for Slot #${slotIndex + 1}',
                      style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              const Text('Choose a widget to place on your Command Center:',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 16),
              if (availableEntries.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                      child: Text('All available widgets are already placed on your dashboard.',
                          style: TextStyle(color: Colors.grey))),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: availableEntries.length,
                    separatorBuilder: (_, __) => const Divider(height: 8),
                    itemBuilder: (context, idx) {
                      final item = availableEntries[idx];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blueAccent.withValues(alpha: 0.12),
                          child: Text('${idx + 1}',
                              style: const TextStyle(
                                  color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(item.value,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        trailing: const Icon(Icons.add_circle_outline, color: Colors.blueAccent),
                        onTap: () {
                          Navigator.pop(ctx);
                          setState(() {
                            _slotWidgets[slotIndex] = item.key;
                          });
                          _saveSlots();
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showRemoveWidgetDialog(int slotIndex, String type) {
    final title = _availableWidgetTypes[type] ?? 'Widget';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Remove $title?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text(
          'Do you want to remove this widget from your Command Center? You can re-add it or pick another widget anytime.',
          style: TextStyle(color: Colors.grey[700], fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _removeWidget(slotIndex);
            },
            child: const Text('Remove Widget'),
          ),
        ],
      ),
    );
  }

  void _removeWidget(int slotIndex) {
    setState(() {
      _slotWidgets[slotIndex] = null;
    });
    _saveSlots();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);

    if (_isLoadingSlots) {
      return Scaffold(
        backgroundColor: bgColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildGreetingHeader(isDark),
              const SizedBox(height: 6),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return GridView.builder(
                      physics: const BouncingScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: (constraints.maxWidth / 2) / (constraints.maxHeight / 4),
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: 8,
                      itemBuilder: (context, index) {
                        final widgetType = _slotWidgets[index];
                        if (widgetType == null) {
                          return _buildEmptySlotTile(index, isDark);
                        }
                        return _buildWidgetTile(index, widgetType, isDark);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGreetingHeader(bool isDark) {
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
    String greetingText;
    String greetingEmoji;
    if (hour < 12) {
      greetingText = 'Good Morning';
      greetingEmoji = '👋';
    } else if (hour < 17) {
      greetingText = 'Good Afternoon';
      greetingEmoji = '☀️';
    } else if (hour < 21) {
      greetingText = 'Good Evening';
      greetingEmoji = '🌆';
    } else {
      greetingText = 'Good Night';
      greetingEmoji = '🌙';
    }

    final formattedDate = DateFormat('EEEE, MMMM d').format(DateTime.now());

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greetingText, $cleanName $greetingEmoji',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                formattedDate,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white60 : Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              if (widget.onNavigateToFeature != null) {
                widget.onNavigateToFeature!('voice_assistant');
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withValues(alpha: isDark ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.mic_rounded, color: Colors.blueAccent, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    'Buddy AI',
                    style: GoogleFonts.outfit(
                      color: Colors.blueAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
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

  Widget _buildEmptySlotTile(int index, bool isDark) {
    final cardBg = isDark ? const Color(0xFF1E293B).withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.8);
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08);

    return InkWell(
      onTap: () => _showAddWidgetSheet(index),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor, style: BorderStyle.solid, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add_rounded, color: Colors.blueAccent, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              '+ Add Widget',
              style: GoogleFonts.outfit(
                color: Colors.blueAccent,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWidgetTile(int slotIndex, String type, bool isDark) {
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.09) : Colors.black.withValues(alpha: 0.06);

    Widget content;
    switch (type) {
      case 'gold_price':
        content = _buildGoldWidget(isDark);
        break;
      case 'bank_accounts':
        content = _buildBankAccountsWidget(isDark);
        break;
      case 'expenses':
        content = _buildExpensesWidget(isDark);
        break;
      case 'shifts':
        content = _buildShiftsWidget(isDark);
        break;
      case 'events_walkins':
        content = _buildEventsWalkinsWidget(isDark);
        break;
      case 'voice_assistant':
        content = _buildVoiceAssistantWidget(isDark);
        break;
      case 'weather':
        content = _buildWeatherWidget(isDark);
        break;
      case 'reminders':
        content = _buildRemindersWidget(isDark);
        break;
      case 'daily_reminders':
        content = _buildDailyRemindersWidget(isDark);
        break;
      case 'notes':
        content = _buildNotesWidget(isDark);
        break;
      default:
        content = const Center(child: Text('Unknown Widget'));
    }

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            if (widget.onNavigateToFeature != null) {
              widget.onNavigateToFeature!(type);
            }
          },
          onLongPress: () => _showRemoveWidgetDialog(slotIndex, type),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
            child: content,
          ),
        ),
      ),
    );
  }

  Widget _buildGoldWidget(bool isDark) {
    final price = _latestGoldPrice?.price ?? 6830.0;
    final priceStr = '₹${price.toStringAsFixed(0)}';
    final changeVal = _latestGoldPrice?.priceChange ?? 25.0;
    final isPositive = changeVal >= 0;
    final changeText = '${isPositive ? "+" : ""}₹${changeVal.abs().toStringAsFixed(0)} Today';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(Icons.monetization_on_rounded, color: Colors.amber, size: 14),
                ),
                const SizedBox(width: 5),
                Text('Gold Rate',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87)),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                '22K',
                style: TextStyle(
                  color: Colors.amber,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              priceStr,
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w900,
                fontSize: 22,
                color: Colors.amber,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: isPositive
                    ? const Color(0xFF10B981).withValues(alpha: 0.15)
                    : const Color(0xFFF43F5E).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                changeText,
                style: TextStyle(
                  color: isPositive ? const Color(0xFF10B981) : const Color(0xFFF43F5E),
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        Text(
          'Live 22K / 1g • Tap for Details',
          style: TextStyle(
            fontSize: 9.5,
            color: isDark ? Colors.white54 : Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildBankAccountsWidget(bool isDark) {
    double totalBalance = 0.0;
    for (var acc in _bankAccounts) {
      totalBalance += (acc['currentBalance'] as num? ?? acc['balance'] as num? ?? 0.0).toDouble();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.indigoAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(Icons.account_balance_rounded, color: Colors.indigoAccent, size: 14),
                ),
                const SizedBox(width: 5),
                Text('Bank Balances',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87)),
              ],
            ),
            Text(
              '${_bankAccounts.length} Banks',
              style: const TextStyle(
                color: Colors.indigoAccent,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        if (_bankAccounts.isEmpty)
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('No Bank Accounts',
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text('Tap to connect', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
              ],
            ),
          )
        else
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ..._bankAccounts.take(2).map((acc) {
                final name = (acc['name'] ?? 'Bank').toString();
                final bal = (acc['currentBalance'] as num? ?? acc['balance'] as num? ?? 0.0).toDouble();
                final balStr = NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(bal);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1.5),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                      Text(
                        balStr,
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: isDark ? Colors.lightBlueAccent : Colors.indigo,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        Text(
          _bankAccounts.length > 2
              ? '+${_bankAccounts.length - 2} more • Total: ${NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(totalBalance)}'
              : 'Tap to view Accounts',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 9.5,
            color: isDark ? Colors.white54 : Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildExpensesWidget(bool isDark) {
    final formattedCredited =
        NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(_todayCredited);
    final formattedDebited =
        NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(_todayDebited);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF43F5E).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(Icons.swap_vert_rounded, color: Color(0xFFF43F5E), size: 14),
                ),
                const SizedBox(width: 5),
                Text('Today\'s Spent',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87)),
              ],
            ),
            const Text(
              'Live Flow',
              style: TextStyle(
                color: Color(0xFFF43F5E),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('🟢 Credited:',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF10B981))),
                Text(
                  '+$formattedCredited',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: const Color(0xFF10B981),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('🔴 Debited:',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFF43F5E))),
                Text(
                  '-$formattedDebited',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: const Color(0xFFF43F5E),
                  ),
                ),
              ],
            ),
          ],
        ),
        Text(
          'Tap for Smart Bank Tracker',
          style: TextStyle(
            fontSize: 9.5,
            color: isDark ? Colors.white54 : Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildShiftsWidget(bool isDark) {
    String shiftTitle = 'NO SHIFT TODAY';
    String shiftTiming = 'Tap to manage roster';
    Color shiftColor = Colors.orange;

    if (_todayShift != null) {
      final rawType = (_todayShift!['shift_type'] ?? _todayShift!['shiftType'] ?? '').toString().toLowerCase();
      final isOff = rawType == 'week_off' || rawType == 'off' || _todayShift!['is_week_off'] == true || _todayShift!['isWeekOff'] == true;
      if (isOff) {
        shiftTitle = 'WEEK OFF';
        shiftTiming = 'Enjoy your day off! 🏖️';
        shiftColor = Colors.cyan;
      } else {
        shiftTitle = rawType.toUpperCase().replaceAll('_', ' ');
        if (!shiftTitle.contains('SHIFT')) shiftTitle = '$shiftTitle SHIFT';
        final startTime = (_todayShift!['start_time'] ?? _todayShift!['startTime'] ?? '').toString();
        final endTime = (_todayShift!['end_time'] ?? _todayShift!['endTime'] ?? '').toString();
        if (startTime.isNotEmpty && endTime.isNotEmpty) {
          shiftTiming = '$startTime - $endTime';
        } else {
          shiftTiming = (_todayShift!['timing'] ?? _todayShift!['notes'] ?? 'Work Shift Active').toString();
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: shiftColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(Icons.work_history_rounded, color: shiftColor, size: 14),
                ),
                const SizedBox(width: 5),
                Text('Today\'s Shift',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87)),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: shiftColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Text(
                'Today',
                style: TextStyle(
                  color: Colors.orange,
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                shiftTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: shiftColor,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                shiftTiming,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white70 : Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Text(
          'Tap to open Shifts & Roster',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 9.5,
            color: isDark ? Colors.white54 : Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildEventsWalkinsWidget(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.tealAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(Icons.rocket_launch_rounded, color: Colors.teal, size: 14),
                ),
                const SizedBox(width: 5),
                Text('Tech & Walk-Ins',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87)),
              ],
            ),
            const Text(
              'Active',
              style: TextStyle(
                color: Colors.teal,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('🚀 Tech Events:',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                Text(
                  '$_upcomingEventsCount Active',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.teal),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('💼 Walk-In Drives:',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                Text(
                  '$_upcomingWalkinsCount Active',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueAccent),
                ),
              ],
            ),
          ],
        ),
        Text(
          'Tap to explore events',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 9.5,
            color: isDark ? Colors.white54 : Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildVoiceAssistantWidget(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(Icons.mic_rounded, color: Colors.redAccent, size: 14),
                ),
                const SizedBox(width: 5),
                Text('Voice AI',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87)),
              ],
            ),
            const Text(
              'Voice Hub',
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.redAccent.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.mic, color: Colors.white, size: 15),
                  const SizedBox(width: 6),
                  Text(
                    'Ask Buddy',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Text(
          'Instant Voice Actions & Queries',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 9.5,
            color: isDark ? Colors.white54 : Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildWeatherWidget(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(_weatherIcon, color: Colors.blueAccent, size: 14),
                ),
                const SizedBox(width: 5),
                Text('Weather',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87)),
              ],
            ),
            const Text(
              'Live',
              style: TextStyle(
                color: Colors.blueAccent,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _weatherTemp,
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w900,
                fontSize: 22,
                color: Colors.blueAccent,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              _weatherCondition,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ],
        ),
        Text(
          'Tap to refresh weather',
          style: TextStyle(
            fontSize: 9.5,
            color: isDark ? Colors.white54 : Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildRemindersWidget(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.indigoAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(Icons.calendar_month_rounded, color: Colors.indigoAccent, size: 14),
                ),
                const SizedBox(width: 5),
                Text('Calendar',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87)),
              ],
            ),
            Text(
              '$_todayRemindersCount Due',
              style: const TextStyle(
                color: Colors.indigoAccent,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$_todayRemindersCount Today',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: Colors.indigoAccent,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                'Calendar Tasks Scheduled',
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white70 : Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
        Text(
          'Tap to open Calendar',
          style: TextStyle(
            fontSize: 9.5,
            color: isDark ? Colors.white54 : Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildDailyRemindersWidget(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.purpleAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(Icons.alarm_on_rounded, color: Colors.purpleAccent, size: 14),
                ),
                const SizedBox(width: 5),
                Text('Daily Tasks',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87)),
              ],
            ),
            Text(
              '$_dailyRemindersCount Active',
              style: const TextStyle(
                color: Colors.purpleAccent,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$_dailyRemindersCount Routines',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: Colors.purpleAccent,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                'Habit Check-ins & Alerts',
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white70 : Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
        Text(
          'Tap to manage alarms',
          style: TextStyle(
            fontSize: 9.5,
            color: isDark ? Colors.white54 : Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildNotesWidget(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(Icons.note_alt_rounded, color: Colors.teal, size: 14),
                ),
                const SizedBox(width: 5),
                Text('Quick Notes',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87)),
              ],
            ),
            Text(
              '$_totalNotesCount Saved',
              style: const TextStyle(
                color: Colors.teal,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$_totalNotesCount Notes',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: Colors.teal,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                'Personal Drafts & Pinned',
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white70 : Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
        Text(
          'Tap to view notes',
          style: TextStyle(
            fontSize: 9.5,
            color: isDark ? Colors.white54 : Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
