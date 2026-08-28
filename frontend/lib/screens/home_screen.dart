import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/storage_service.dart';
import '../services/gold_service.dart';

class HomeScreen extends StatefulWidget {
  final Function(String featureId)? onNavigateToFeature;

  const HomeScreen({super.key, this.onNavigateToFeature});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final StorageService _storage = StorageService();
  final GoldService _goldService = GoldService();

  // 8 Grid Slot widget IDs saved in SharedPreferences
  List<String?> _slotWidgets = List.filled(8, null);
  bool _isLoadingSlots = true;

  // Live Data Streams / Snapshots
  Map<String, dynamic>? _goldData;
  List<Map<String, dynamic>> _bankAccounts = [];
  Map<String, double> _todayExpenses = {'sent': 0.0, 'received': 0.0};
  Map<String, dynamic>? _nextShift;
  int _upcomingEventsCount = 0;
  int _upcomingWalkinsCount = 0;

  StreamSubscription? _accountsSub;
  StreamSubscription? _eventsSub;
  StreamSubscription? _walkinsSub;
  StreamSubscription? _shiftsSub;

  final Map<String, String> _availableWidgetTypes = {
    'gold_price': '🪙 Gold Price Tracker',
    'bank_accounts': '🏦 Bank Balances',
    'expenses': '💳 Today\'s Expenses',
    'shifts': '💼 Upcoming Work Shifts',
    'events_walkins': '🚀 Tech Events & Walk-Ins',
    'voice_assistant': '🎙️ Voice Assistant',
    'reminders': '🔔 Daily Reminders',
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
    _accountsSub?.cancel();
    _eventsSub?.cancel();
    _walkinsSub?.cancel();
    _shiftsSub?.cancel();
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
          null,
          null,
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

    // 1. Fetch Gold Rate
    _goldService.getLatestGoldPrice().then((data) {
      if (mounted) setState(() => _goldData = data);
    });

    // 2. Fetch Bank Accounts
    _accountsSub = _storage.getBankAccountsStream().listen((accounts) {
      if (mounted) {
        setState(() {
          _bankAccounts = accounts.map((a) => a.toMap()).toList();
        });
      }
    });

    // 3. Fetch Today Expenses
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _storage.getFinanceTransactionsStream().listen((txs) {
      double sent = 0.0;
      double received = 0.0;
      for (final tx in txs) {
        if (tx.date == todayStr) {
          if (tx.type == 'debit' || tx.type == 'expense' || tx.type == 'sent') {
            sent += tx.amount;
          } else if (tx.type == 'credit' || tx.type == 'income' || tx.type == 'received') {
            received += tx.amount;
          }
        }
      }
      if (mounted) {
        setState(() {
          _todayExpenses = {'sent': sent, 'received': received};
        });
      }
    });

    // 4. Fetch Next Shift
    _shiftsSub = _storage.getShiftsStream().listen((shifts) {
      final nowStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final upcoming = shifts.where((s) => s.date.compareTo(nowStr) >= 0).toList();
      upcoming.sort((a, b) => a.date.compareTo(b.date));
      if (mounted) {
        setState(() {
          _nextShift = upcoming.isNotEmpty ? upcoming.first.toMap() : null;
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
        return (data['notInterested'] != true) && ((data['date'] ?? '').toString().compareTo(nowStr) >= 0);
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
        return (data['notInterested'] != true) && ((data['date'] ?? '').toString().compareTo(nowStr) >= 0);
      }).length;
      if (mounted) setState(() => _upcomingWalkinsCount = active);
    });
  }

  void _showAddWidgetSheet(int slotIndex) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
              Text('Select Widget for Slot #${slotIndex + 1}', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Choose a summary widget to display on your command dashboard:', style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 16),
              if (availableEntries.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('All available widgets are already placed on your home dashboard.', style: TextStyle(color: Colors.grey))),
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
                          backgroundColor: Colors.blue.shade50,
                          child: Text('${idx + 1}', style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(item.value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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

  void _removeWidget(int slotIndex) {
    setState(() {
      _slotWidgets[slotIndex] = null;
    });
    _saveSlots();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA);

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
          padding: const EdgeInsets.all(12.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GridView.builder(
                physics: const NeverScrollableScrollPhysics(), // Non-scrollable fits viewport
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: (constraints.maxWidth / 2) / ((constraints.maxHeight - 24) / 4),
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
    return InkWell(
      onTap: () => _showAddWidgetSheet(index),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.white10 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300, style: BorderStyle.solid),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline, color: Colors.blueAccent.shade400, size: 28),
            const SizedBox(height: 6),
            Text(
              '+ Add Widget',
              style: GoogleFonts.outfit(color: Colors.blueAccent.shade400, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWidgetTile(int slotIndex, String type, bool isDark) {
    final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    Widget content;
    switch (type) {
      case 'gold_price':
        content = _buildGoldWidget();
        break;
      case 'bank_accounts':
        content = _buildBankAccountsWidget();
        break;
      case 'expenses':
        content = _buildExpensesWidget();
        break;
      case 'shifts':
        content = _buildShiftsWidget();
        break;
      case 'events_walkins':
        content = _buildEventsWalkinsWidget();
        break;
      case 'voice_assistant':
        content = _buildVoiceAssistantWidget();
        break;
      case 'reminders':
        content = _buildRemindersWidget();
        break;
      case 'notes':
        content = _buildNotesWidget();
        break;
      default:
        content = const Center(child: Text('Unknown Widget'));
    }

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: content,
          ),
          Positioned(
            top: 2,
            right: 2,
            child: IconButton(
              icon: const Icon(Icons.close, size: 14, color: Colors.grey),
              onPressed: () => _removeWidget(slotIndex),
              tooltip: 'Remove Widget',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoldWidget() {
    final price24k = _goldData?['rate24k'] ?? '₹7,450';
    final change = _goldData?['change'] ?? '+₹25';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            const Icon(Icons.monetization_on, color: Colors.amber, size: 18),
            const SizedBox(width: 4),
            Text('Gold Price', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 6),
        Text(price24k, style: const TextStyle(fontWeight: FontWeight.extrabold, fontSize: 16, color: Colors.amber)),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text('24K • $change Today', style: TextStyle(color: Colors.green.shade800, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildBankAccountsWidget() {
    double totalBalance = 0.0;
    for (var acc in _bankAccounts) {
      totalBalance += (acc['balance'] as num? ?? 0.0).toDouble();
    }
    final formattedTotal = NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(totalBalance);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            const Icon(Icons.account_balance, color: Colors.indigo, size: 18),
            const SizedBox(width: 4),
            Text('Bank Balances', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 6),
        Text(formattedTotal, style: const TextStyle(fontWeight: FontWeight.extrabold, fontSize: 16, color: Colors.indigo)),
        const SizedBox(height: 2),
        Text('${_bankAccounts.length} Connected Accounts', style: const TextStyle(color: Colors.grey, fontSize: 10)),
      ],
    );
  }

  Widget _buildExpensesWidget() {
    final sent = _todayExpenses['sent'] ?? 0.0;
    final formattedSent = NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(sent);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            const Icon(Icons.credit_card, color: Colors.redAccent, size: 18),
            const SizedBox(width: 4),
            Text('Today\'s Spent', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 6),
        Text(formattedSent, style: const TextStyle(fontWeight: FontWeight.extrabold, fontSize: 16, color: Colors.redAccent)),
        const SizedBox(height: 2),
        Text('Outgoing Today', style: const TextStyle(color: Colors.grey, fontSize: 10)),
      ],
    );
  }

  Widget _buildShiftsWidget() {
    final shiftTitle = _nextShift?['title'] ?? 'No Upcoming Shift';
    final shiftDate = _nextShift?['date'] ?? '-';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            const Icon(Icons.work_history, color: Colors.orange, size: 18),
            const SizedBox(width: 4),
            Text('Next Work Shift', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 6),
        Text(shiftTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 2),
        Text(shiftDate, style: const TextStyle(color: Colors.grey, fontSize: 10)),
      ],
    );
  }

  Widget _buildEventsWalkinsWidget() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            const Icon(Icons.rocket_launch, color: Colors.green, size: 18),
            const SizedBox(width: 4),
            Text('Tech & Walk-Ins', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Chip(
              label: Text('Events: $_upcomingEventsCount', style: const TextStyle(fontSize: 10, color: Colors.white)),
              backgroundColor: Colors.green.shade700,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 4),
            Chip(
              label: Text('Drives: $_upcomingWalkinsCount', style: const TextStyle(fontSize: 10, color: Colors.white)),
              backgroundColor: Colors.blue.shade700,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVoiceAssistantWidget() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            const Icon(Icons.mic, color: Colors.redAccent, size: 18),
            const SizedBox(width: 4),
            Text('Voice Assistant', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () {
              if (widget.onNavigateToFeature != null) {
                widget.onNavigateToFeature!('voice_assistant');
              }
            },
            icon: const Icon(Icons.mic, size: 14),
            label: const Text('Ask Gemini', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildRemindersWidget() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            const Icon(Icons.notifications_active, color: Colors.purple, size: 18),
            const SizedBox(width: 4),
            Text('Daily Reminders', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 6),
        const Text('Scheduled Reminders', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.purple)),
        const SizedBox(height: 2),
        const Text('Tap to open reminders', style: TextStyle(color: Colors.grey, fontSize: 10)),
      ],
    );
  }

  Widget _buildNotesWidget() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            const Icon(Icons.note_alt, color: Colors.teal, size: 18),
            const SizedBox(width: 4),
            Text('Quick Notes', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 6),
        const Text('Personal Drafts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal)),
        const SizedBox(height: 2),
        const Text('Tap to open notes', style: TextStyle(color: Colors.grey, fontSize: 10)),
      ],
    );
  }
}
