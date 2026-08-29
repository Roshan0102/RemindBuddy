import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
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
  double _todaySpent = 0.0;
  Map<String, dynamic>? _nextShift;
  int _upcomingEventsCount = 0;
  int _upcomingWalkinsCount = 0;
  int _todayRemindersCount = 0;
  int _totalNotesCount = 0;
  int _dailyRemindersCount = 0;

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
    'gold_price': '🪙 Gold Price Tracker',
    'bank_accounts': '🏦 Bank Balances',
    'expenses': '💳 Today\'s Expenses',
    'shifts': '💼 Upcoming Work Shifts',
    'events_walkins': '🚀 Tech Events & Walk-Ins',
    'voice_assistant': '🎙️ Voice Assistant',
    'reminders': '📅 Calendar Reminders',
    'daily_reminders': '🔔 Daily Reminders',
    'notes': '📝 Quick Notes Summary',
  };

  @override
  void initState() {
    super.initState();
    _loadSlots();
    _loadDashboardData();
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

  void _loadDashboardData() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // 1. Fetch Gold Rate Stream
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

    // 3. Fetch Today's Spent Stream from 'finance_transactions' and 'sms_transactions'
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    double manualSpent = 0.0;
    double smsSpent = 0.0;

    _txSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('finance_transactions')
        .snapshots()
        .listen((snap) {
      double spent = 0.0;
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
          if (dtStr == todayStr && (type == 'expense' || type == 'debit')) {
            spent += (data['amount'] as num? ?? 0.0).toDouble();
          }
        }
      }
      manualSpent = spent;
      if (mounted) {
        setState(() {
          _todaySpent = manualSpent + smsSpent;
        });
      }
    });

    _smsTxSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('sms_transactions')
        .snapshots()
        .listen((snap) {
      double spent = 0.0;
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
          if (dtStr == todayStr && (type == 'debit' || type == 'expense')) {
            spent += (data['amount'] as num? ?? 0.0).toDouble();
          }
        }
      }
      smsSpent = spent;
      if (mounted) {
        setState(() {
          _todaySpent = manualSpent + smsSpent;
        });
      }
    });

    // 4. Fetch Next Work Shift from 'shifts/{rosterMonth}/daily_shifts'
    final now = DateTime.now();
    final currentRosterMonth = DateFormat('yyyy-MM').format(now);
    final nextRosterMonth = DateFormat('yyyy-MM').format(DateTime(now.year, now.month + 1, 1));

    _shiftsSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('shifts')
        .doc(currentRosterMonth)
        .collection('daily_shifts')
        .snapshots()
        .listen((snap) {
      final nowStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final upcoming = snap.docs.where((d) {
        final data = d.data();
        final date = (data['date'] ?? '').toString();
        final type = (data['shift_type'] ?? data['shiftType'] ?? '').toString().toLowerCase();
        return date.compareTo(nowStr) >= 0 && type != 'week_off' && type != 'off';
      }).toList();

      upcoming.sort((a, b) =>
          (a.data()['date'] ?? '').toString().compareTo((b.data()['date'] ?? '').toString()));

      if (upcoming.isNotEmpty) {
        if (mounted) {
          setState(() {
            _nextShift = upcoming.first.data();
          });
        }
      } else {
        // Check next month if empty
        FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('shifts')
            .doc(nextRosterMonth)
            .collection('daily_shifts')
            .get()
            .then((nextSnap) {
          final nextUpcoming = nextSnap.docs.where((d) {
            final data = d.data();
            final date = (data['date'] ?? '').toString();
            final type = (data['shift_type'] ?? data['shiftType'] ?? '').toString().toLowerCase();
            return date.compareTo(nowStr) >= 0 && type != 'week_off' && type != 'off';
          }).toList();

          nextUpcoming.sort((a, b) =>
              (a.data()['date'] ?? '').toString().compareTo((b.data()['date'] ?? '').toString()));

          if (mounted) {
            setState(() {
              _nextShift = nextUpcoming.isNotEmpty ? nextUpcoming.first.data() : null;
            });
          }
        }).catchError((_) {});
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
          'Do you want to remove this widget from your Command Center? You can add another widget to this slot anytime.',
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
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GridView.builder(
                physics: const BouncingScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: (constraints.maxWidth / 2) / ((constraints.maxHeight - 16) / 4),
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
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add_rounded, color: Colors.blueAccent, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              '+ Add Widget',
              style: GoogleFonts.outfit(
                color: Colors.blueAccent,
                fontWeight: FontWeight.bold,
                fontSize: 13,
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
            blurRadius: 10,
            offset: const Offset(0, 4),
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
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
            child: content,
          ),
        ),
      ),
    );
  }

  Widget _buildGoldWidget(bool isDark) {
    final priceStr = _latestGoldPrice != null
        ? '₹${_latestGoldPrice!.price.toStringAsFixed(0)}'
        : '₹7,450';
    final changeVal = _latestGoldPrice?.priceChange ?? 25.0;
    final isPositive = changeVal >= 0;
    final changeText = '${isPositive ? "+" : ""}₹${changeVal.abs().toStringAsFixed(0)}';

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
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.monetization_on_rounded, color: Colors.amber, size: 16),
                ),
                const SizedBox(width: 6),
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
                color: isPositive ? Colors.green.withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '24K • $changeText',
                style: TextStyle(
                  color: isPositive ? Colors.greenAccent.shade700 : Colors.redAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
            Text(
              'Live 24K / 1g • Tap for Analytics',
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white54 : Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBankAccountsWidget(bool isDark) {
    double totalBalance = 0.0;
    for (var acc in _bankAccounts) {
      totalBalance += (acc['currentBalance'] as num? ?? acc['balance'] as num? ?? 0.0).toDouble();
    }
    final formattedTotal =
        NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(totalBalance);

    String bankNamesStr = '';
    if (_bankAccounts.isNotEmpty) {
      final names = _bankAccounts
          .map((a) => (a['name'] ?? 'Bank').toString())
          .take(2)
          .join(', ');
      bankNamesStr = _bankAccounts.length > 2 ? '$names +${_bankAccounts.length - 2}' : names;
    } else {
      bankNamesStr = 'Tap to Add Bank';
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
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.indigoAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.account_balance_rounded, color: Colors.indigoAccent, size: 16),
                ),
                const SizedBox(width: 6),
                Text('Bank Balances',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87)),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.indigoAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${_bankAccounts.length} Banks',
                style: const TextStyle(
                  color: Colors.indigoAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formattedTotal,
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w900,
                fontSize: 22,
                color: isDark ? Colors.lightBlueAccent : Colors.indigo,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              bankNamesStr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white54 : Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildExpensesWidget(bool isDark) {
    final formattedSpent =
        NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(_todaySpent);

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
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF43F5E).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.credit_card_rounded, color: Color(0xFFF43F5E), size: 16),
                ),
                const SizedBox(width: 6),
                Text('Today\'s Spent',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87)),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF43F5E).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'Outflow',
                style: TextStyle(
                  color: Color(0xFFF43F5E),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formattedSpent,
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w900,
                fontSize: 22,
                color: const Color(0xFFF43F5E),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Debits & Manual Expenses',
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white54 : Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildShiftsWidget(bool isDark) {
    String shiftTitle = 'No Shift';
    String shiftTiming = 'No upcoming shift';
    String dayLabel = '';

    if (_nextShift != null) {
      final rawType = (_nextShift!['shift_type'] ?? _nextShift!['shiftType'] ?? 'Work Shift').toString();
      shiftTitle = rawType.toUpperCase().replaceAll('_', ' ');
      shiftTiming = (_nextShift!['timing'] ?? _nextShift!['notes'] ?? '').toString();
      final dateStr = (_nextShift!['date'] ?? '').toString();

      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final tomorrowStr = DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 1)));

      if (dateStr == todayStr) {
        dayLabel = 'Today';
      } else if (dateStr == tomorrowStr) {
        dayLabel = 'Tomorrow';
      } else if (dateStr.isNotEmpty) {
        try {
          dayLabel = DateFormat('MMM d').format(DateTime.parse(dateStr));
        } catch (_) {
          dayLabel = dateStr;
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
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.work_history_rounded, color: Colors.orange, size: 16),
                ),
                const SizedBox(width: 6),
                Text('Next Shift',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87)),
              ],
            ),
            if (dayLabel.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  dayLabel,
                  style: const TextStyle(
                    color: Colors.orange,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              shiftTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w900,
                fontSize: 17,
                color: Colors.orange,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              shiftTiming.isNotEmpty ? shiftTiming : 'Tap to manage roster',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white54 : Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEventsWalkinsWidget(bool isDark) {
    final totalOpportunities = _upcomingEventsCount + _upcomingWalkinsCount;

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
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.tealAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.rocket_launch_rounded, color: Colors.teal, size: 16),
                ),
                const SizedBox(width: 6),
                Text('Career & Tech',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87)),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$_upcomingWalkinsCount Drives',
                style: const TextStyle(
                  color: Colors.teal,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$totalOpportunities Active',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w900,
                fontSize: 20,
                color: Colors.teal,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$_upcomingEventsCount Tech Events • $_upcomingWalkinsCount Walk-Ins',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white54 : Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVoiceAssistantWidget(bool isDark) {
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
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.mic_rounded, color: Colors.redAccent, size: 16),
                ),
                const SizedBox(width: 6),
                Text('Voice AI',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87)),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'Gemini 2.5',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ask Gemini',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w900,
                fontSize: 20,
                color: Colors.redAccent,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Instant Voice Actions & Queries',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white54 : Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
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
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.indigoAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.calendar_month_rounded, color: Colors.indigoAccent, size: 16),
                ),
                const SizedBox(width: 6),
                Text('Calendar',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87)),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.indigoAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$_todayRemindersCount Due',
                style: const TextStyle(
                  color: Colors.indigoAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$_todayRemindersCount Today',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w900,
                fontSize: 20,
                color: Colors.indigoAccent,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Personal & Shared Calendar Reminders',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white54 : Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
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
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.purpleAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.alarm_on_rounded, color: Colors.purpleAccent, size: 16),
                ),
                const SizedBox(width: 6),
                Text('Daily Tasks',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87)),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.purpleAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$_dailyRemindersCount Active',
                style: const TextStyle(
                  color: Colors.purpleAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$_dailyRemindersCount Routines',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w900,
                fontSize: 20,
                color: Colors.purpleAccent,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Recurring Alarms & Habit Check-ins',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white54 : Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
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
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.note_alt_rounded, color: Colors.teal, size: 16),
                ),
                const SizedBox(width: 6),
                Text('Quick Notes',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87)),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$_totalNotesCount Saved',
                style: const TextStyle(
                  color: Colors.teal,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$_totalNotesCount Notes',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w900,
                fontSize: 20,
                color: Colors.teal,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Personal Drafts & Pinned Checklists',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white54 : Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
