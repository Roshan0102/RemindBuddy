import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../models/bank_account.dart';
import '../models/finance_transaction.dart';
import '../models/recurring_bill.dart';
import '../models/debt_record.dart';
import '../models/group_split.dart';
import '../models/sms_transaction.dart';
import '../services/finance_service.dart';
import '../services/sms_parser_service.dart';
import '../widgets/nightly_expense_tag_sheet.dart';

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FinanceService _financeService = FinanceService();
  static const EventChannel _smsStreamChannel = EventChannel('com.remindbuddy/sms_stream');
  bool _isScanningInbox = false;
  bool _isSyncingStudySms = false;
  DateTime _smsMonthFilter = DateTime.now();
  final ValueNotifier<int> _smsSubTabNotifier = ValueNotifier<int>(0);
  final PageController _smsPageController = PageController();

  int? _selectedFeatureIndex;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _smsMonthFilter = DateTime(now.year, now.month);
    _tabController = TabController(length: 2, vsync: this);
    _initSmsRealtimeListener();
    _financeService.checkAndProcessPendingBackgroundSms();
  }

  void _initSmsRealtimeListener() {
    _smsStreamChannel.receiveBroadcastStream().listen((dynamic event) {
      if (event is Map) {
        final String sender = event['sender']?.toString() ?? '';
        final String body = event['body']?.toString() ?? '';
        final int timestamp = (event['timestamp'] is num) ? (event['timestamp'] as num).toInt() : 0;

        final parsed = SmsParserService.parseSms(sender, body, timestamp);
        if (parsed != null) {
          _financeService.saveSmsTransaction(parsed);
        }
      }
    }, onError: (err) {
      print('SMS EventChannel stream error: $err');
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _smsPageController.dispose();
    _smsSubTabNotifier.dispose();
    super.dispose();
  }

  Widget _getFeatureTitle(int index) {
    switch (index) {
      case 0:
        return const Text('Bank Accounts 🏦', style: TextStyle(fontWeight: FontWeight.bold));
      case 1:
        return const Text('Bills & Subscriptions 🧾', style: TextStyle(fontWeight: FontWeight.bold));
      case 2:
        return const Text('Debts & Lended Money 🤝', style: TextStyle(fontWeight: FontWeight.bold));
      case 3:
        return const Text('Group Expense Splitter 👥', style: TextStyle(fontWeight: FontWeight.bold));
      case 4:
        return const Text('Smart Bank Tracker 💳', style: TextStyle(fontWeight: FontWeight.bold));
      default:
        return const Text('FinanceBuddy', style: TextStyle(fontWeight: FontWeight.bold));
    }
  }

  Widget _buildFeatureWidget(int index) {
    switch (index) {
      case 0:
        return _buildAccountsTab();
      case 1:
        return _buildBillsTab();
      case 2:
        return _buildDebtsTab();
      case 3:
        return _buildGroupSplitterTab();
      case 4:
        return _buildSmsTrackerTab();
      default:
        return _buildAccountsTab();
    }
  }

  Widget _buildFinanceHubGrid() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color subtextColor = isDark ? Colors.white70 : Colors.black54;
    final Color cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;

    final List<Map<String, dynamic>> features = [
      {
        'index': 4,
        'title': 'Smart Bank Tracker 💳',
        'subtitle': 'Real-time bank SMS parsing, monthly spend analytics & 1-tap review',
        'icon': Icons.account_balance_wallet_rounded,
        'gradient': [const Color(0xFF3B82F6), const Color(0xFF1D4ED8)],
      },
      {
        'index': 0,
        'title': 'Bank Accounts 🏦',
        'subtitle': 'Combined net worth, multi-bank balance & manual transactions',
        'icon': Icons.account_balance_rounded,
        'gradient': [const Color(0xFF0EA5E9), const Color(0xFF0369A1)],
      },
      {
        'index': 1,
        'title': 'Bills & Subscriptions 🧾',
        'subtitle': 'Monthly recurring bill reminders & subscription tracker',
        'icon': Icons.receipt_long_rounded,
        'gradient': [const Color(0xFFA855F7), const Color(0xFF7E22CE)],
      },
      {
        'index': 2,
        'title': 'Debts & Lended Money 🤝',
        'subtitle': 'Track who owes you money and payments you borrowed',
        'icon': Icons.handshake_rounded,
        'gradient': [const Color(0xFFF59E0B), const Color(0xFFB45309)],
      },
      {
        'index': 3,
        'title': 'Group Expense Splitter 👥',
        'subtitle': 'Split trip expenses, dinners & shared bills with friends',
        'icon': Icons.groups_rounded,
        'gradient': [const Color(0xFF10B981), const Color(0xFF047857)],
      },
    ];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.blueAccent, size: 28),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Finance Hub 💳',
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                Text(
                  'Select a feature to manage your money',
                  style: TextStyle(color: subtextColor, fontSize: 13),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),

        ...features.map((feat) {
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            elevation: isDark ? 4 : 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            color: cardBg,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                setState(() {
                  _selectedFeatureIndex = feat['index'] as int;
                });
              },
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: cardBg,
                  border: Border.all(color: (feat['gradient'] as List<Color>).first.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: feat['gradient'] as List<Color>),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(feat['icon'] as IconData, color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            feat['title'] as String,
                            style: GoogleFonts.outfit(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            feat['subtitle'] as String,
                            style: TextStyle(color: subtextColor, fontSize: 12, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, color: subtextColor, size: 18),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _selectedFeatureIndex == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectedFeatureIndex != null) {
          setState(() {
            _selectedFeatureIndex = null;
          });
        }
      },
      child: _selectedFeatureIndex == null
          ? Scaffold(
              appBar: AppBar(
                title: Text(
                  'FinanceBuddy',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                ),
              ),
              body: _buildFinanceHubGrid(),
            )
          : Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () {
                    setState(() {
                      _selectedFeatureIndex = null;
                    });
                  },
                ),
                title: _getFeatureTitle(_selectedFeatureIndex!),
              ),
              body: _buildFeatureWidget(_selectedFeatureIndex!),
            ),
    );
  }

  // ============================================================================
  // TAB 1: ACCOUNTS & TRANSACTIONS
  // ============================================================================

  Widget _buildAccountsTab() {
    return StreamBuilder<List<BankAccount>>(
      stream: _financeService.getAccountsStream(),
      builder: (context, accountsSnap) {
        if (accountsSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final accounts = accountsSnap.data ?? [];
        final double totalNetWorth = accounts.fold(0.0, (sum, acc) => sum + acc.currentBalance);

        return StreamBuilder<List<FinanceTransaction>>(
          stream: _financeService.getTransactionsStream(),
          builder: (context, txSnap) {
            final bool isDark = Theme.of(context).brightness == Brightness.dark;
            final Color textColor = isDark ? Colors.white : const Color(0xFF0F172A);
            final transactions = txSnap.data ?? [];

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Total Net Worth Card
                Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  color: Colors.blue.shade800,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total Combined Net Worth',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '₹${NumberFormat('#,##,##0.00').format(totalNetWorth)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _showAddAccountDialog(context),
                                icon: const Icon(Icons.add_card, size: 18),
                                label: const Text('Add Account'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.blue.shade900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: accounts.isEmpty
                                    ? null
                                    : () => _showAddTransactionDialog(context, accounts),
                                icon: const Icon(Icons.add_circle, size: 18),
                                label: const Text('Add Transaction'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Accounts Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Your Accounts',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${accounts.length} Accounts',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (accounts.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text('No bank accounts added yet. Tap "Add Account" to start tracking!'),
                    ),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: accounts.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 0.88,
                    ),
                    itemBuilder: (context, index) {
                      final acc = accounts[index];
                      final Color accColor = Color(acc.colorHex);
                      final bool isPositive = acc.currentBalance >= 0;

                      return Container(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: accColor.withOpacity(0.5), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: isDark ? Colors.black26 : Colors.grey.withOpacity(0.12),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Top Row: Small Icon & Compact Menu
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: accColor.withOpacity(0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(_getIconData(acc.iconName), color: accColor, size: 14),
                                ),
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: PopupMenuButton<String>(
                                    padding: EdgeInsets.zero,
                                    iconSize: 14,
                                    onSelected: (val) {
                                      if (val == 'delete') {
                                        _financeService.deleteAccount(acc.id);
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(value: 'delete', child: Text('Delete Account', style: TextStyle(fontSize: 12))),
                                    ],
                                    icon: const Icon(Icons.more_vert, size: 14, color: Colors.grey),
                                  ),
                                ),
                              ],
                            ),

                            // Middle: Bank Name (BIGGER & BOLD)
                            Text(
                              acc.name,
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: textColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),

                            // Bottom: Balance (BIGGER & PROMINENT)
                            Text(
                              '₹${NumberFormat('#,##,##0').format(acc.currentBalance)}',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: isPositive ? Colors.green.shade600 : Colors.redAccent,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                const SizedBox(height: 24),
                const Text(
                  'Recent Transactions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                if (transactions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: Text('No transactions recorded yet.')),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: transactions.length,
                    itemBuilder: (context, index) {
                      final tx = transactions[index];
                      final isIncome = tx.type == 'income';
                      final accountName = accounts.firstWhere((a) => a.id == tx.accountId,
                          orElse: () => BankAccount(
                                id: '',
                                name: 'Unknown',
                                accountType: '',
                                initialBalance: 0,
                                currentBalance: 0,
                                colorHex: 0,
                                iconName: '',
                                updatedAt: DateTime.now(),
                              )).name;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isIncome ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                            child: Icon(
                              isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                              color: isIncome ? Colors.green : Colors.red,
                            ),
                          ),
                          title: Text(
                            tx.note.isNotEmpty ? tx.note : tx.category,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text('$accountName • ${DateFormat('MMM d, h:mm a').format(tx.timestamp)}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${isIncome ? '+' : '-'}₹${NumberFormat('#,##,##0.00').format(tx.amount)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: isIncome ? Colors.green : Colors.red,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                                onPressed: () => _financeService.deleteTransaction(tx),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================================================
  // TAB 2: RECURRING BILLS
  // ============================================================================

  Widget _buildBillsTab() {
    return StreamBuilder<List<RecurringBill>>(
      stream: _financeService.getBillsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final bills = snapshot.data ?? [];

        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showAddBillDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('Add Bill'),
          ),
          body: bills.isEmpty
              ? const Center(
                  child: Text('No recurring bills added. Tap "Add Bill" to set reminders!'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: bills.length,
                  itemBuilder: (context, index) {
                    final bill = bills[index];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.purple.withOpacity(0.1),
                          child: const Icon(Icons.calendar_today, color: Colors.purple),
                        ),
                        title: Text(bill.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          '${bill.category} • Due: ${DateFormat('MMM d, yyyy').format(bill.dueDate)} (${bill.frequency})',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '₹${NumberFormat('#,##,##0').format(bill.amount)}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.purple),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, color: Colors.blueAccent),
                              onPressed: () => _showAddBillDialog(context, existingBill: bill),
                              tooltip: 'Edit Bill',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _financeService.deleteBill(bill.id),
                              tooltip: 'Delete Bill',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  // ============================================================================
  // TAB 3: LENT / BORROWED DEBTS
  // ============================================================================

  Widget _buildDebtsTab() {
    return StreamBuilder<List<DebtRecord>>(
      stream: _financeService.getDebtsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final debts = snapshot.data ?? [];
        final totalLent = debts
            .where((d) => d.type == 'lent' && !d.isSettled)
            .fold(0.0, (sum, d) => sum + d.amount);
        final totalBorrowed = debts
            .where((d) => d.type == 'borrowed' && !d.isSettled)
            .fold(0.0, (sum, d) => sum + d.amount);

        return StreamBuilder<List<BankAccount>>(
          stream: _financeService.getAccountsStream(),
          builder: (context, accountsSnap) {
            final accounts = accountsSnap.data ?? [];

            return Scaffold(
              floatingActionButton: FloatingActionButton.extended(
                onPressed: () => _showAddDebtDialog(context, accounts),
                icon: const Icon(Icons.add),
                label: const Text('Add Debt / Loan'),
              ),
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Debt Summary Row
                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          color: Colors.green.shade50,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('You Lent (They owe you)',
                                    style: TextStyle(fontSize: 12, color: Colors.green)),
                                const SizedBox(height: 4),
                                Text(
                                  '₹${NumberFormat('#,##,##0').format(totalLent)}',
                                  style: const TextStyle(
                                      fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Card(
                          color: Colors.red.shade50,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('You Borrowed (You owe)',
                                    style: TextStyle(fontSize: 12, color: Colors.red)),
                                const SizedBox(height: 4),
                                Text(
                                  '₹${NumberFormat('#,##,##0').format(totalBorrowed)}',
                                  style: const TextStyle(
                                      fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (debts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Center(child: Text('No debt or loan records added yet.')),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: debts.length,
                      itemBuilder: (context, index) {
                        final debt = debts[index];
                        final isLent = debt.type == 'lent';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: debt.isSettled
                                  ? Colors.grey.withOpacity(0.2)
                                  : (isLent ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1)),
                              child: Icon(
                                debt.isSettled
                                    ? Icons.check
                                    : (isLent ? Icons.arrow_upward : Icons.arrow_downward),
                                color: debt.isSettled ? Colors.grey : (isLent ? Colors.green : Colors.red),
                              ),
                            ),
                            title: Text(
                              debt.personName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                decoration: debt.isSettled ? TextDecoration.lineThrough : null,
                              ),
                            ),
                            subtitle: Text(
                              '${isLent ? 'Lent' : 'Borrowed'} • ${DateFormat('MMM d, yyyy').format(debt.date)}${debt.note.isNotEmpty ? ' • ${debt.note}' : ''}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '₹${NumberFormat('#,##,##0').format(debt.amount)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: debt.isSettled ? Colors.grey : (isLent ? Colors.green : Colors.red),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (!debt.isSettled)
                                  ElevatedButton(
                                    onPressed: () => _showSettleDebtDialog(context, debt, accounts),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    ),
                                    child: const Text('Settle', style: TextStyle(fontSize: 12)),
                                  )
                                else
                                  const Chip(
                                    label: Text('Settled', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                    backgroundColor: Colors.transparent,
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20),
                                  onPressed: () => _financeService.deleteDebt(debt.id),
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
      },
    );
  }

  // ============================================================================
  // TAB 4: GROUP BILL SPLITTER
  // ============================================================================

  Widget _buildGroupSplitterTab() {
    return StreamBuilder<List<GroupEvent>>(
      stream: _financeService.getGroupEventsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final groupEvents = snapshot.data ?? [];

        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showAddGroupEventDialog(context),
            icon: const Icon(Icons.group_add),
            label: const Text('New Trip / Group'),
          ),
          body: groupEvents.isEmpty
              ? const Center(
                  child: Text('No group events created. Tap "New Trip / Group" to split expenses!'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: groupEvents.length,
                  itemBuilder: (context, index) {
                    final group = groupEvents[index];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        title: Text(group.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 6),
                            Text('Members: ${group.members.join(", ")}'),
                            const SizedBox(height: 4),
                            Text(
                              'Created: ${DateFormat('MMM d, yyyy').format(group.createdAt)}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.arrow_forward_ios, size: 16),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _financeService.deleteGroupEvent(group.id),
                            ),
                          ],
                        ),
                        onTap: () => _openGroupEventDetailScreen(context, group),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  // ============================================================================
  // DIALOGS & HELPER METHODS
  // ============================================================================

  IconData _getIconData(String name) {
    switch (name) {
      case 'account_balance':
        return Icons.account_balance;
      case 'credit_card':
        return Icons.credit_card;
      case 'savings':
        return Icons.savings;
      case 'payments':
        return Icons.payments;
      case 'wallet':
        return Icons.account_balance_wallet;
      default:
        return Icons.account_balance;
    }
  }

  void _showAddAccountDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final balanceCtrl = TextEditingController(text: '0');
    String selectedType = 'savings';
    int selectedColor = 0xFF2196F3;
    String selectedIcon = 'account_balance';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Bank Account / Wallet'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Account Name (e.g. HDFC Salary, SBI, Cash)'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedType,
                decoration: const InputDecoration(labelText: 'Account Type'),
                items: const [
                  DropdownMenuItem(value: 'salary', child: Text('Salary Account')),
                  DropdownMenuItem(value: 'savings', child: Text('Savings Account')),
                  DropdownMenuItem(value: 'spending', child: Text('Daily Spending Account')),
                  DropdownMenuItem(value: 'cash', child: Text('Physical Cash / Wallet')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (val) => selectedType = val ?? 'savings',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: balanceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Starting Balance (₹)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty) return;
              final bal = double.tryParse(balanceCtrl.text.trim()) ?? 0.0;

              _financeService.addAccount(BankAccount(
                id: '',
                name: nameCtrl.text.trim(),
                accountType: selectedType,
                initialBalance: bal,
                currentBalance: bal,
                colorHex: selectedColor,
                iconName: selectedIcon,
                updatedAt: DateTime.now(),
              ));
              Navigator.pop(context);
            },
            child: const Text('Add Account'),
          ),
        ],
      ),
    );
  }

  void _showAddTransactionDialog(BuildContext context, List<BankAccount> accounts) {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController(text: '');
    String selectedAccountId = accounts.first.id;
    String type = 'expense';
    String selectedCategory = 'Food & Dining';

    final List<Map<String, dynamic>> categories = [
      {'name': 'Food & Dining', 'icon': Icons.fastfood, 'color': Colors.orange},
      {'name': 'Fuel & Travel', 'icon': Icons.local_gas_station, 'color': Colors.redAccent},
      {'name': 'Groceries', 'icon': Icons.shopping_basket, 'color': Colors.green},
      {'name': 'Bills & Utilities', 'icon': Icons.receipt_long, 'color': Colors.blue},
      {'name': 'Shopping', 'icon': Icons.shopping_bag, 'color': Colors.purple},
      {'name': 'Self Transfer', 'icon': Icons.swap_horiz_rounded, 'color': Colors.indigoAccent},
      {'name': 'Borrowed', 'icon': Icons.south_west_rounded, 'color': Colors.amber.shade700},
      {'name': 'Borrowed Repaid', 'icon': Icons.check_circle_outline_rounded, 'color': Colors.orange.shade700},
      {'name': 'Lended', 'icon': Icons.north_east_rounded, 'color': Colors.teal},
      {'name': 'Loan Repaid', 'icon': Icons.task_alt_rounded, 'color': Colors.green.shade700},
      {'name': 'Entertainment', 'icon': Icons.movie, 'color': Colors.pink},
      {'name': 'Personal Care', 'icon': Icons.spa, 'color': Colors.deepOrangeAccent},
      {'name': 'Ignored / Not Needed', 'icon': Icons.block_rounded, 'color': Colors.blueGrey},
      {'name': 'Others', 'icon': Icons.more_horiz, 'color': Colors.grey},
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Transaction 💳'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Expense (-)', textAlign: TextAlign.center),
                        selected: type == 'expense',
                        selectedColor: Colors.red.shade100,
                        onSelected: (val) => setDialogState(() => type = 'expense'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Income (+)', textAlign: TextAlign.center),
                        selected: type == 'income',
                        selectedColor: Colors.green.shade100,
                        onSelected: (val) => setDialogState(() => type = 'income'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedAccountId,
                  decoration: const InputDecoration(labelText: 'Select Account'),
                  items: accounts
                      .map((a) => DropdownMenuItem(value: a.id, child: Text('${a.name} (₹${a.currentBalance.toStringAsFixed(0)})')))
                      .toList(),
                  onChanged: (val) => selectedAccountId = val!,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount (₹)'),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Select Category:',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: categories.map((cat) {
                    final bool isSelected = selectedCategory == cat['name'];
                    final Color catColor = cat['color'] as Color;

                    return ChoiceChip(
                      avatar: Icon(cat['icon'] as IconData, size: 14, color: isSelected ? Colors.white : catColor),
                      label: Text(
                        cat['name'] as String,
                        style: TextStyle(
                          fontSize: 11,
                          color: isSelected ? Colors.white : null,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: catColor,
                      onSelected: (selected) {
                        if (selected) {
                          setDialogState(() {
                            selectedCategory = cat['name'] as String;
                          });
                        }
                      },
                    );
                  }).toList(),
                ),
                if (selectedCategory == 'Others' || selectedCategory == 'Borrowed' || selectedCategory == 'Lended') ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: noteCtrl,
                    decoration: InputDecoration(
                      labelText: selectedCategory == 'Borrowed'
                          ? 'Borrowed From (Person / Reason)'
                          : selectedCategory == 'Lended'
                              ? 'Lended To (Person / Reason)'
                              : 'Custom Category / Reason',
                      hintText: selectedCategory == 'Borrowed'
                          ? 'e.g. Rahul, John...'
                          : selectedCategory == 'Lended'
                              ? 'e.g. Alex, Friend...'
                              : 'Type custom reason...',
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final amt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                if (amt <= 0) return;

                final customNote = noteCtrl.text.trim();
                final finalCategory = (selectedCategory == 'Others' && customNote.isNotEmpty)
                    ? customNote
                    : selectedCategory;

                if (selectedCategory == 'Others' && customNote.isNotEmpty) {
                  await _financeService.saveUserCustomTag(customNote);
                }

                await _financeService.addTransaction(FinanceTransaction(
                  id: '',
                  accountId: selectedAccountId,
                  type: type,
                  amount: amt,
                  category: finalCategory,
                  note: customNote.isNotEmpty ? customNote : selectedCategory,
                  timestamp: DateTime.now(),
                ));

                // If Category is Borrowed or Lended, also create a DebtRecord entry in Debts & Lended Money feature!
                if (selectedCategory == 'Borrowed' || selectedCategory == 'Lended') {
                  final String debtType = selectedCategory == 'Borrowed' ? 'borrowed' : 'lent';
                  final String personName = customNote.isNotEmpty ? customNote : 'Person';
                  final String noteText = customNote.isNotEmpty ? customNote : 'Manually added in Bank Accounts';

                  await _financeService.addDebt(
                    DebtRecord(
                      id: '',
                      personName: personName,
                      type: debtType,
                      amount: amt,
                      note: noteText,
                      date: DateTime.now(),
                      isSettled: false,
                      accountId: selectedAccountId,
                    ),
                    updateAccountBalance: false, // Balance already updated by addTransaction above
                  );
                }

                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddNotificationOptionDialog(BuildContext parentContext, Function(String) onAdd) {
    showDialog(
      context: parentContext,
      builder: (ctx) => SimpleDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        children: [
          SimpleDialogOption(
            onPressed: () {
              onAdd('On the day at 9 AM');
              Navigator.pop(ctx);
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('On the day at 9 AM', style: TextStyle(fontSize: 15)),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              onAdd('The day before at 9 AM');
              Navigator.pop(ctx);
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('The day before at 9 AM', style: TextStyle(fontSize: 15)),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              onAdd('2 days before at 9 AM');
              Navigator.pop(ctx);
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('2 days before at 9 AM', style: TextStyle(fontSize: 15)),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              onAdd('1 week before at 9 AM');
              Navigator.pop(ctx);
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('1 week before at 9 AM', style: TextStyle(fontSize: 15)),
            ),
          ),
          const Divider(height: 1),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _showCustomNotificationDialog(parentContext, onAdd);
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Custom...', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
            ),
          ),
        ],
      ),
    );
  }

  void _showCustomNotificationDialog(BuildContext parentContext, Function(String) onAdd) {
    final numCtrl = TextEditingController(text: '1');
    String unit = 'Day before';
    TimeOfDay selectedTime = const TimeOfDay(hour: 9, minute: 0);

    showDialog(
      context: parentContext,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setCustomState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Custom notification', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: numCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 12),
                RadioListTile<String>(
                  title: const Text('Day before'),
                  value: 'Day before',
                  groupValue: unit,
                  dense: true,
                  onChanged: (val) {
                    if (val != null) setCustomState(() => unit = val);
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Week'),
                  value: 'Week',
                  groupValue: unit,
                  dense: true,
                  onChanged: (val) {
                    if (val != null) setCustomState(() => unit = val);
                  },
                ),
                const Divider(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'At ${selectedTime.format(context)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  trailing: const Icon(Icons.access_time_rounded, color: Colors.blueAccent),
                  onTap: () async {
                    final picked = await showTimePicker(context: context, initialTime: selectedTime);
                    if (picked != null) {
                      setCustomState(() => selectedTime = picked);
                    }
                  },
                ),
                const Divider(height: 16),
                RadioListTile<String>(
                  title: const Text('As notification'),
                  value: 'notification',
                  groupValue: 'notification',
                  dense: true,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                final n = int.tryParse(numCtrl.text.trim()) ?? 1;
                final formattedTime = selectedTime.format(context);
                String rule = '';
                if (unit == 'Day before') {
                  if (n == 0) {
                    rule = 'On the day at $formattedTime';
                  } else if (n == 1) {
                    rule = 'The day before at $formattedTime';
                  } else {
                    rule = '$n days before at $formattedTime';
                  }
                } else {
                  if (n == 1) {
                    rule = '1 week before at $formattedTime';
                  } else {
                    rule = '$n weeks before at $formattedTime';
                  }
                }
                onAdd(rule);
                Navigator.pop(ctx);
              },
              child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddBillDialog(BuildContext context, {RecurringBill? existingBill}) {
    final titleCtrl = TextEditingController(text: existingBill?.title ?? '');
    final amountCtrl = TextEditingController(text: existingBill != null ? existingBill.amount.toString() : '');
    final notesCtrl = TextEditingController(text: existingBill?.notes ?? '');
    final customDaysCtrl = TextEditingController(text: '15');

    String dateSelectionMode = existingBill?.startDate != null ? 'start_date' : 'due_date';
    DateTime selectedDate = existingBill?.startDate ?? existingBill?.dueDate ?? DateTime.now().add(const Duration(days: 7));
    String selectedFrequency = 'monthly';
    if (existingBill != null) {
      final f = existingBill.frequency.toLowerCase();
      if (f.contains('15')) selectedFrequency = '15_days';
      else if (f.contains('30')) selectedFrequency = '30_days';
      else if (f.contains('45')) selectedFrequency = '45_days';
      else if (f.contains('60')) selectedFrequency = '60_days';
      else if (f.contains('weekly')) selectedFrequency = 'weekly';
      else if (f.contains('yearly')) selectedFrequency = 'yearly';
      else if (f.contains('monthly')) selectedFrequency = 'monthly';
      else if (f.contains('days')) {
        selectedFrequency = 'custom';
        final match = RegExp(r'(\d+)').firstMatch(f);
        if (match != null) customDaysCtrl.text = match.group(1)!;
      }
    }

    String category = existingBill?.category ?? 'Utilities';
    List<String> notificationRules = existingBill?.notifications != null
        ? List<String>.from(existingBill!.notifications)
        : ['On the day at 9 AM'];

    DateTime calculateNextDue(DateTime inputDate, String mode, String freq, int customDays) {
      if (mode == 'due_date') return inputDate;

      final now = DateTime.now();
      DateTime next = inputDate;
      int intervalDays = 0;
      if (freq == '15_days') intervalDays = 15;
      else if (freq == '30_days') intervalDays = 30;
      else if (freq == '45_days') intervalDays = 45;
      else if (freq == '60_days') intervalDays = 60;
      else if (freq == 'custom') intervalDays = customDays > 0 ? customDays : 30;

      int safety = 0;
      final todayTrunc = DateTime(now.year, now.month, now.day);
      while (next.isBefore(todayTrunc) && safety < 1000) {
        safety++;
        if (freq == 'monthly') {
          next = DateTime(next.year, next.month + 1, next.day);
        } else if (freq == 'weekly') {
          next = next.add(const Duration(days: 7));
        } else if (freq == 'yearly') {
          next = DateTime(next.year + 1, next.month, next.day);
        } else {
          next = next.add(Duration(days: intervalDays > 0 ? intervalDays : 30));
        }
      }
      return next;
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final customDaysVal = int.tryParse(customDaysCtrl.text.trim()) ?? 30;
          final calculatedDue = calculateNextDue(selectedDate, dateSelectionMode, selectedFrequency, customDaysVal);

          return AlertDialog(
            title: Text(existingBill != null ? 'Edit Bill / Subscription' : 'Add Recurring Bill / Subscription'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: 'Title (e.g. Broadband, Rent, Netflix)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Amount (₹)'),
                  ),
                  const SizedBox(height: 14),

                  const Text('Set Date By:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Next Due Date', style: TextStyle(fontSize: 11)),
                          selected: dateSelectionMode == 'due_date',
                          onSelected: (sel) {
                            if (sel) {
                              setDialogState(() {
                                dateSelectionMode = 'due_date';
                                selectedDate = DateTime.now().add(const Duration(days: 7));
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Start / Last Paid', style: TextStyle(fontSize: 11)),
                          selected: dateSelectionMode == 'start_date',
                          onSelected: (sel) {
                            if (sel) {
                              setDialogState(() {
                                dateSelectionMode = 'start_date';
                                selectedDate = DateTime.now();
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      dateSelectionMode == 'start_date'
                          ? 'Start Date: ${DateFormat('MMM d, yyyy').format(selectedDate)}'
                          : 'Due Date: ${DateFormat('MMM d, yyyy').format(selectedDate)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: dateSelectionMode == 'start_date'
                        ? Text('Calculated Next Due: ${DateFormat('MMM d, yyyy').format(calculatedDue)}', style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.w600))
                        : null,
                    trailing: const Icon(Icons.calendar_today, color: Colors.blueAccent),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: dateSelectionMode == 'start_date' ? DateTime(2020) : DateTime.now().subtract(const Duration(days: 30)),
                        lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDate = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: selectedFrequency,
                    decoration: const InputDecoration(labelText: 'Frequency'),
                    items: const [
                      DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                      DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                      DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                      DropdownMenuItem(value: '15_days', child: Text('Every 15 Days')),
                      DropdownMenuItem(value: '30_days', child: Text('Every 30 Days')),
                      DropdownMenuItem(value: '45_days', child: Text('Every 45 Days')),
                      DropdownMenuItem(value: '60_days', child: Text('Every 60 Days')),
                      DropdownMenuItem(value: 'custom', child: Text('Custom Days Interval')),
                    ],
                    onChanged: (val) {
                      setDialogState(() {
                        selectedFrequency = val ?? 'monthly';
                      });
                    },
                  ),
                  if (selectedFrequency == 'custom') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: customDaysCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Interval in Days (e.g. 15, 45, 90)',
                        hintText: 'Enter number of days',
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                  ],

                  // NOTIFICATIONS SECTION (Google Calendar Style)
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Icon(Icons.notifications_none_rounded, color: Colors.blueAccent, size: 20),
                      SizedBox(width: 8),
                      Text('Notifications', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...notificationRules.map((rule) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(rule, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                              InkWell(
                                onTap: () {
                                  setDialogState(() {
                                    notificationRules.remove(rule);
                                  });
                                },
                                child: const Icon(Icons.close_rounded, size: 18, color: Colors.grey),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () {
                          _showAddNotificationOptionDialog(context, (newRule) {
                            setDialogState(() {
                              if (!notificationRules.contains(newRule)) {
                                notificationRules.add(newRule);
                              }
                            });
                          });
                        },
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            '+ Add notification',
                            style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  if (titleCtrl.text.trim().isEmpty) return;
                  final amt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                  String freqStr = selectedFrequency;
                  if (selectedFrequency == '15_days') {
                    freqStr = 'Every 15 Days';
                  } else if (selectedFrequency == '30_days') {
                    freqStr = 'Every 30 Days';
                  } else if (selectedFrequency == '45_days') {
                    freqStr = 'Every 45 Days';
                  } else if (selectedFrequency == '60_days') {
                    freqStr = 'Every 60 Days';
                  } else if (selectedFrequency == 'custom') {
                    final days = int.tryParse(customDaysCtrl.text.trim()) ?? 30;
                    freqStr = 'Every $days Days';
                  }

                  final finalDueDate = calculateNextDue(selectedDate, dateSelectionMode, selectedFrequency, customDaysVal);

                  if (existingBill != null) {
                    _financeService.updateBill(RecurringBill(
                      id: existingBill.id,
                      title: titleCtrl.text.trim(),
                      amount: amt,
                      category: category,
                      dueDate: finalDueDate,
                      startDate: dateSelectionMode == 'start_date' ? selectedDate : existingBill.startDate,
                      frequency: freqStr,
                      notifications: notificationRules.isNotEmpty ? notificationRules : ['On the day at 9 AM'],
                      notes: notesCtrl.text.trim(),
                      isActive: existingBill.isActive,
                    ));
                  } else {
                    _financeService.addBill(RecurringBill(
                      id: '',
                      title: titleCtrl.text.trim(),
                      amount: amt,
                      category: category,
                      dueDate: finalDueDate,
                      startDate: dateSelectionMode == 'start_date' ? selectedDate : null,
                      frequency: freqStr,
                      notifications: notificationRules.isNotEmpty ? notificationRules : ['On the day at 9 AM'],
                      notes: notesCtrl.text.trim(),
                    ));
                  }
                  Navigator.pop(context);
                },
                child: Text(existingBill != null ? 'Update Bill' : 'Add Bill'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddDebtDialog(BuildContext context, List<BankAccount> accounts) {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String type = 'lent'; // 'lent' (they owe me) or 'borrowed' (I owe them)
    String? selectedAccountId = accounts.isNotEmpty ? accounts.first.id : null;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Debt / Loan Record'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('I Lent Money\n(They owe me)', textAlign: TextAlign.center),
                        selected: type == 'lent',
                        selectedColor: Colors.green.shade100,
                        onSelected: (val) => setDialogState(() => type = 'lent'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('I Borrowed\n(I owe them)', textAlign: TextAlign.center),
                        selected: type == 'borrowed',
                        selectedColor: Colors.red.shade100,
                        onSelected: (val) => setDialogState(() => type = 'borrowed'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Person Name (e.g. Rahul, Dad, Friend)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount (₹)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(labelText: 'Note (e.g., Dinner split, Emergency loan)'),
                ),
                const SizedBox(height: 12),
                if (accounts.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: selectedAccountId,
                    decoration: const InputDecoration(labelText: 'Deduct/Add to Account (Optional)'),
                    items: accounts
                        .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                        .toList(),
                    onChanged: (val) => selectedAccountId = val,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) return;
                final amt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                if (amt <= 0) return;

                _financeService.addDebt(DebtRecord(
                  id: '',
                  personName: nameCtrl.text.trim(),
                  type: type,
                  amount: amt,
                  note: noteCtrl.text.trim(),
                  date: DateTime.now(),
                  accountId: selectedAccountId,
                ));
                Navigator.pop(context);
              },
              child: const Text('Save Record'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSettleDebtDialog(BuildContext context, DebtRecord debt, List<BankAccount> accounts) {
    String? selectedAccountId = accounts.isNotEmpty ? accounts.first.id : null;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Settle Up with ${debt.personName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              debt.type == 'lent'
                  ? 'Mark ₹${debt.amount} as paid back by ${debt.personName}?'
                  : 'Mark ₹${debt.amount} as paid to ${debt.personName}?',
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 16),
            if (accounts.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: selectedAccountId,
                decoration: const InputDecoration(labelText: 'Deposit/Deduct Account'),
                items: accounts
                    .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                    .toList(),
                onChanged: (val) => selectedAccountId = val,
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              _financeService.settleDebt(debt, selectedAccountId ?? '');
              Navigator.pop(context);
            },
            child: const Text('Confirm Settlement'),
          ),
        ],
      ),
    );
  }

  void _showAddGroupEventDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    final membersCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Trip / Group Event'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'Event Name (e.g. Goa Trip, Team Dinner)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: membersCtrl,
              decoration: const InputDecoration(
                labelText: 'Member Names (comma separated)',
                hintText: 'e.g. Roshan, Rahul, Vikas, Priya',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (titleCtrl.text.trim().isEmpty) return;
              final rawMembers = membersCtrl.text.split(',');
              final members = rawMembers.map((m) => m.trim()).where((m) => m.isNotEmpty).toList();

              if (members.isEmpty) return;

              _financeService.addGroupEvent(GroupEvent(
                id: '',
                title: titleCtrl.text.trim(),
                members: members,
                createdAt: DateTime.now(),
              ));
              Navigator.pop(context);
            },
            child: const Text('Create Event'),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // TAB 5: AUTOMATED SMS BANK TRACKER
  // ============================================================================

  Widget _buildSmsTrackerTab() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color subtextColor = isDark ? Colors.white70 : Colors.black54;
    final Color cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final Color summaryBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);

    final String? currentUid = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<DocumentSnapshot>(
      stream: currentUid != null
          ? FirebaseFirestore.instance.collection('users').doc(currentUid).snapshots()
          : const Stream.empty(),
      builder: (context, userSnap) {
        bool isSmsStudyEnabled = false;
        if (userSnap.hasData && userSnap.data?.data() != null) {
          final data = userSnap.data!.data() as Map<String, dynamic>;
          final List<dynamic> modules = data['enabledModules'] ?? [];
          isSmsStudyEnabled = modules.contains('sms_study');
        }

        return StreamBuilder<List<SmsTransaction>>(
          stream: _financeService.getSmsTransactionsStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final activeTransactions = (snapshot.data ?? []).where((tx) {
              return tx.category != 'Ignored / Not Needed' && tx.category != 'Ignored';
            }).toList();

            final monthTransactions = activeTransactions.where((tx) {
              return tx.timestamp.year == _smsMonthFilter.year && tx.timestamp.month == _smsMonthFilter.month;
            }).toList();

            final pendingUntagged = monthTransactions.where((t) => !t.isVerified).toList();

            double totalSpent = 0.0;
            double totalReceived = 0.0;
            final Map<String, double> categoryTotals = {};

            for (final tx in monthTransactions) {
              if (tx.type == 'Debit') {
                totalSpent += tx.amount;
                final cat = tx.isVerified ? tx.category : 'Uncategorized';
                categoryTotals[cat] = (categoryTotals[cat] ?? 0.0) + tx.amount;
              } else {
                totalReceived += tx.amount;
              }
            }

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    children: [
                      // Admin-Controlled SMS Study Banner
                      if (isSmsStudyEnabled) ...[
                        Card(
                          elevation: isDark ? 3 : 1,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          color: isDark ? const Color(0xFF1E3A8A) : Colors.blue.shade50,
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                const Icon(Icons.science_rounded, color: Colors.blueAccent, size: 28),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'SMS Study Sync (Admin Active)',
                                        style: GoogleFonts.outfit(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: textColor,
                                        ),
                                      ),
                                      Text(
                                        'Sync last 15 days SMS samples to Cloud for AI pattern research',
                                        style: TextStyle(color: subtextColor, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blueAccent,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: _isSyncingStudySms
                                      ? null
                                      : () async {
                                          setState(() => _isSyncingStudySms = true);
                                          final count = await _financeService.uploadSmsStudySamples(days: 15);
                                          setState(() => _isSyncingStudySms = false);
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('Successfully uploaded $count SMS samples to Cloud for AI Study!'),
                                                backgroundColor: Colors.green,
                                              ),
                                            );
                                          }
                                        },
                                  icon: _isSyncingStudySms
                                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                      : const Icon(Icons.cloud_upload_rounded, size: 16),
                                  label: Text(_isSyncingStudySms ? 'Syncing...' : 'Sync 15 Days'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      // Static Month Selector Bar
                      Card(
                        elevation: isDark ? 3 : 1,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        color: cardBg,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.chevron_left, color: Colors.blueAccent, size: 28),
                                    onPressed: () {
                                      setState(() {
                                        _smsMonthFilter = DateTime(_smsMonthFilter.year, _smsMonthFilter.month - 1);
                                      });
                                    },
                                  ),
                                  Text(
                                    DateFormat('MMMM yyyy').format(_smsMonthFilter),
                                    style: GoogleFonts.outfit(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: textColor,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.chevron_right, color: Colors.blueAccent, size: 28),
                                    onPressed: () {
                                      setState(() {
                                        _smsMonthFilter = DateTime(_smsMonthFilter.year, _smsMonthFilter.month + 1);
                                      });
                                    },
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    tooltip: 'Bank Header Rules ⚙️',
                                    icon: const Icon(Icons.settings_suggest_rounded, color: Colors.blueAccent, size: 22),
                                    onPressed: () => _showCustomHeaderRulesDialog(context),
                                  ),
                                  IconButton(
                                    tooltip: 'Sync Bank SMS',
                                    icon: _isScanningInbox
                                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent))
                                        : const Icon(Icons.sync_rounded, color: Colors.blueAccent, size: 22),
                                    onPressed: _isScanningInbox ? null : _showSmsSyncDialog,
                                  ),
                                  IconButton(
                                    tooltip: 'Delete Month Transactions',
                                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
                                    onPressed: () => _confirmDeleteMonthTransactions(context),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Sub-Tab Selector Pills (Transactions List | Analytics & Budget)
                      ValueListenableBuilder<int>(
                        valueListenable: _smsSubTabNotifier,
                        builder: (context, currentSubTab, _) {
                          return Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF0F172A) : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      _smsSubTabNotifier.value = 0;
                                      _smsPageController.animateToPage(0, duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      decoration: BoxDecoration(
                                        color: currentSubTab == 0 ? Colors.blueAccent : Colors.transparent,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Center(
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.list_alt_rounded, size: 16, color: currentSubTab == 0 ? Colors.white : subtextColor),
                                            const SizedBox(width: 6),
                                            Text(
                                              'Transactions (${monthTransactions.length})',
                                              style: TextStyle(
                                                color: currentSubTab == 0 ? Colors.white : subtextColor,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      _smsSubTabNotifier.value = 1;
                                      _smsPageController.animateToPage(1, duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      decoration: BoxDecoration(
                                        color: currentSubTab == 1 ? Colors.blueAccent : Colors.transparent,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Center(
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.insert_chart_outlined_rounded, size: 16, color: currentSubTab == 1 ? Colors.white : subtextColor),
                                            const SizedBox(width: 6),
                                            Text(
                                              'Analytics & Budget',
                                              style: TextStyle(
                                                color: currentSubTab == 1 ? Colors.white : subtextColor,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Swipeable PageView Body (Bidirectional Smooth Swiping)
                Expanded(
                  child: PageView(
                    controller: _smsPageController,
                    physics: const BouncingScrollPhysics(),
                    onPageChanged: (idx) {
                      if (_smsSubTabNotifier.value != idx) {
                        _smsSubTabNotifier.value = idx;
                      }
                    },
                    children: [
                      // PAGE 0: Transactions List View
                      StreamBuilder<List<Map<String, String>>>(
                        stream: _financeService.getCustomHeaderBankRulesStream(),
                        builder: (context, headerSnap) {
                          final customRules = headerSnap.data ?? [];
                          final int extraHeaderCount = (pendingUntagged.isNotEmpty ? 1 : 0) + 1;
                          final int totalItemCount = extraHeaderCount + (monthTransactions.isEmpty ? 1 : monthTransactions.length);

                          return ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            itemCount: totalItemCount,
                            itemBuilder: (context, index) {
                              int currIdx = index;
                              if (pendingUntagged.isNotEmpty) {
                                if (currIdx == 0) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: Card(
                                      elevation: 3,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                      color: Colors.amber.shade900.withOpacity(0.85),
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.nightlight_round, color: Colors.white, size: 28),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    '${pendingUntagged.length} Untagged Expenses',
                                                    style: GoogleFonts.outfit(
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                  const Text(
                                                    'Tap to tag reasons & sync your bank balances',
                                                    style: TextStyle(color: Colors.white70, fontSize: 11),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.white,
                                                foregroundColor: Colors.black87,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              ),
                                              onPressed: () {
                                                showModalBottomSheet(
                                                  context: context,
                                                  isScrollControlled: true,
                                                  backgroundColor: Colors.transparent,
                                                  builder: (ctx) => NightlyExpenseTagSheet(pendingTransactions: pendingUntagged),
                                                );
                                              },
                                              child: const Text('Review All', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                currIdx--;
                              }

                              if (currIdx == 0) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Text(
                                    '${DateFormat('MMMM').format(_smsMonthFilter)} Transactions (${monthTransactions.length})',
                                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: textColor),
                                  ),
                                );
                              }
                              currIdx--;

                              if (monthTransactions.isEmpty) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 40),
                                  child: Center(
                                    child: Text(
                                      'No SMS bank transactions recorded for ${DateFormat('MMMM yyyy').format(_smsMonthFilter)}.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: subtextColor),
                                    ),
                                  ),
                                );
                              }

                              final tx = monthTransactions[currIdx];
                              final isDebit = tx.type == 'Debit';
                              final String cleanSender = tx.sender.trim().toUpperCase();
                              String resolvedBankName = tx.bankName;

                              for (final rule in customRules) {
                                final pattern = (rule['pattern'] ?? '').toUpperCase();
                                final bankName = rule['bankName'] ?? '';
                                if (pattern.isNotEmpty && bankName.isNotEmpty && cleanSender.contains(pattern)) {
                                  resolvedBankName = bankName;
                                  break;
                                }
                              }

                              final bool isGenericBank = resolvedBankName == 'Bank' || resolvedBankName.toLowerCase() == 'unknown';
                              final effectiveTx = tx.copyWith(bankName: resolvedBankName);

                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                color: cardBg,
                                elevation: isDark ? 2 : 1,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(
                                    color: isGenericBank ? Colors.redAccent : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                                    width: isGenericBank ? 1.8 : 1.0,
                                  ),
                                ),
                                child: ListTile(
                                  onTap: () {
                                    showModalBottomSheet(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (ctx) => NightlyExpenseTagSheet(pendingTransactions: [effectiveTx]),
                                    );
                                  },
                                  leading: CircleAvatar(
                                    backgroundColor: isDebit ? Colors.red.shade900.withOpacity(0.3) : Colors.green.shade900.withOpacity(0.3),
                                    child: Icon(
                                      isDebit ? Icons.arrow_upward : Icons.arrow_downward,
                                      color: isDebit ? Colors.redAccent : Colors.green,
                                    ),
                                  ),
                                  title: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            resolvedBankName,
                                            style: TextStyle(
                                              color: isGenericBank ? Colors.redAccent : textColor,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                          if (isGenericBank) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.red.withOpacity(0.2),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Text(
                                                '⚠️ Assign Bank',
                                                style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      Text(
                                        '${isDebit ? '-' : '+'}${NumberFormat.currency(symbol: '₹', decimalDigits: 2).format(tx.amount)}',
                                        style: TextStyle(
                                          color: isDebit ? Colors.redAccent : Colors.green,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 2),
                                      Text('Payee: ${tx.payee}', style: TextStyle(color: subtextColor, fontSize: 12)),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            DateFormat('dd MMM, hh:mm a').format(tx.timestamp),
                                            style: TextStyle(color: subtextColor, fontSize: 11),
                                          ),
                                          Row(
                                            children: [
                                              InkWell(
                                                onTap: () => _showSmsDetailsDialog(context, tx),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  margin: const EdgeInsets.only(right: 6),
                                                  decoration: BoxDecoration(
                                                    color: Colors.blue.withOpacity(0.15),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(color: Colors.blue.withOpacity(0.4), width: 0.8),
                                                  ),
                                                  child: const Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.sms_rounded, size: 11, color: Colors.blueAccent),
                                                      SizedBox(width: 3),
                                                      Text('SMS 📩', style: TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: tx.isVerified ? Colors.green.withOpacity(0.2) : Colors.amber.withOpacity(0.2),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  tx.isVerified ? tx.category : 'Untagged (Tap to tag)',
                                                  style: TextStyle(
                                                    color: tx.isVerified ? (isDark ? Colors.greenAccent : Colors.green.shade800) : (isDark ? Colors.amberAccent : Colors.amber.shade900),
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),

    // PAGE 1: Analytics & Monthly Budget Dashboard View
    _buildAnalyticsAndBudgetTab(
      monthTransactions: monthTransactions,
      totalSpent: totalSpent,
      totalReceived: totalReceived,
      categoryTotals: categoryTotals,
      isDark: isDark,
      cardBg: cardBg,
      textColor: textColor,
      subtextColor: subtextColor,
    ),
  ],
),
),
],
);
      },
    );
  },
);
  }

  void _showSmsSyncDialog() {
    final String currentMonthName = DateFormat('MMMM yyyy').format(_smsMonthFilter);

    showDialog(
      context: context,
      builder: (ctx) {
        final bool isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          title: Row(
            children: [
              const Icon(Icons.sync_rounded, color: Colors.blueAccent),
              const SizedBox(width: 10),
              Text(
                'Sync Bank SMS',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Select SMS scan range for your bank transactions:'),
              const SizedBox(height: 16),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
                leading: const Icon(Icons.calendar_month_rounded, color: Colors.indigoAccent),
                title: Text('Selected Month ($currentMonthName)'),
                subtitle: const Text('Strictly scan 1st to end of selected month'),
                onTap: () {
                  Navigator.pop(ctx);
                  final startCutoff = DateTime(_smsMonthFilter.year, _smsMonthFilter.month, 1, 0, 0, 0);
                  final endCutoff = DateTime(_smsMonthFilter.year, _smsMonthFilter.month + 1, 0, 23, 59, 59);
                  final daysNeeded = DateTime.now().difference(startCutoff).inDays + 2;
                  _runSmsScan(daysNeeded > 0 ? daysNeeded : 31, startCutoff: startCutoff, endCutoff: endCutoff);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
                leading: const Icon(Icons.history_rounded, color: Colors.blueAccent),
                title: const Text('Last 15 Days'),
                subtitle: const Text('Scan SMS from past 15 days'),
                onTap: () {
                  Navigator.pop(ctx);
                  _runSmsScan(15);
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
                leading: const Icon(Icons.date_range_rounded, color: Colors.teal),
                title: const Text('Last 30 Days'),
                subtitle: const Text('Scan SMS from past 30 days'),
                onTap: () {
                  Navigator.pop(ctx);
                  _runSmsScan(30);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _runSmsScan(int days, {DateTime? startCutoff, DateTime? endCutoff}) async {
    setState(() => _isScanningInbox = true);
    final count = await _financeService.scanPastSmsInbox(days: days, startCutoff: startCutoff, endCutoff: endCutoff);
    setState(() => _isScanningInbox = false);
    if (mounted) {
      final rangeText = startCutoff != null ? DateFormat('MMMM yyyy').format(startCutoff) : 'past $days days';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(count > 0 ? 'Detected & saved $count new SMS transactions for $rangeText!' : 'No new bank SMS detected for $rangeText.'),
          backgroundColor: count > 0 ? Colors.green : Colors.blueGrey,
        ),
      );
    }
  }

  void _confirmDeleteMonthTransactions(BuildContext context) {
    final String monthYearText = DateFormat('MMMM yyyy').format(_smsMonthFilter);
    showDialog(
      context: context,
      builder: (ctx) {
        final bool isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          title: Row(
            children: [
              const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
              const SizedBox(width: 10),
              Text(
                'Delete $monthYearText?',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to delete ALL SMS transactions recorded for $monthYearText?\n\nThis action cannot be undone.',
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
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                final deletedCount = await _financeService.deleteSmsTransactionsForMonth(_smsMonthFilter);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Deleted $deletedCount transactions for $monthYearText.'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              },
              child: const Text('Delete All'),
            ),
          ],
        );
      },
    );
  }

  void _openGroupEventDetailScreen(BuildContext context, GroupEvent group) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GroupEventDetailScreen(group: group)),
    );
  }

  void _showSmsDetailsDialog(BuildContext context, SmsTransaction tx) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final Color textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color subtextColor = isDark ? Colors.white70 : Colors.black54;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.sms_rounded, color: Colors.blue, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'SMS Raw Details 📩',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SMS SENDER HEADER',
                      style: TextStyle(color: Colors.blue.shade700, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      tx.sender.isNotEmpty ? tx.sender : (tx.bankName.isNotEmpty ? tx.bankName : 'Unknown Header'),
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: textColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Timing Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RECEIVED TIMING',
                      style: TextStyle(color: subtextColor, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('dd MMMM yyyy, hh:mm:ss a').format(tx.timestamp),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Detected Bank & Payee
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('DETECTED BANK', style: TextStyle(color: subtextColor, fontSize: 10, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          Text(tx.bankName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('EXTRACTED PAYEE', style: TextStyle(color: subtextColor, fontSize: 10, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          Text(tx.payee, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Raw Body Text
              Text(
                'RAW SMS MESSAGE BODY:',
                style: TextStyle(color: subtextColor, fontSize: 11, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                ),
                child: SelectableText(
                  tx.notes.isNotEmpty ? tx.notes : 'No raw SMS body recorded.',
                  style: TextStyle(fontSize: 13, color: textColor, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsAndBudgetTab({
    required List<SmsTransaction> monthTransactions,
    required double totalSpent,
    required double totalReceived,
    required Map<String, double> categoryTotals,
    required bool isDark,
    required Color cardBg,
    required Color textColor,
    required Color subtextColor,
  }) {
    final double netSavings = totalReceived - totalSpent;
    final maxCategoryAmount = categoryTotals.values.isEmpty
        ? 1.0
        : categoryTotals.values.reduce((a, b) => a > b ? a : b);

    final Map<int, double> dailySpending = {};
    for (var tx in monthTransactions) {
      if (tx.type == 'Debit') {
        final day = tx.timestamp.day;
        dailySpending[day] = (dailySpending[day] ?? 0.0) + tx.amount;
      }
    }

    return StreamBuilder<Map<String, double>>(
      stream: _financeService.getCategoryBudgetsStream(),
      builder: (context, budgetSnap) {
        final budgets = budgetSnap.data ?? {};

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          children: [
            // 1. Monthly Cashflow Summary Card
            Card(
              elevation: isDark ? 3 : 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              color: cardBg,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Monthly Cashflow',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: netSavings >= 0 ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            netSavings >= 0 ? 'Surplus +₹${netSavings.toStringAsFixed(0)}' : 'Deficit -₹${(-netSavings).toStringAsFixed(0)}',
                            style: TextStyle(
                              color: netSavings >= 0 ? Colors.green : Colors.redAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.arrow_upward, size: 14, color: Colors.redAccent),
                                  const SizedBox(width: 4),
                                  Text('Total Spent', style: TextStyle(color: subtextColor, fontSize: 11)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(totalSpent),
                                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.redAccent),
                              ),
                            ],
                          ),
                        ),
                        Container(height: 35, width: 1, color: isDark ? Colors.white12 : Colors.grey.shade300),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.arrow_downward, size: 14, color: Colors.green),
                                    const SizedBox(width: 4),
                                    Text('Total Received', style: TextStyle(color: subtextColor, fontSize: 11)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(totalReceived),
                                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 2. Category Expense Breakdown Chart Card
            Card(
              elevation: isDark ? 3 : 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              color: cardBg,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Category Expense Breakdown 📊',
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: textColor),
                    ),
                    const SizedBox(height: 14),
                    if (categoryTotals.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Center(
                          child: Text('No verified expenses for this month.', style: TextStyle(color: subtextColor, fontSize: 12)),
                        ),
                      )
                    else ...[
                      // Visual Pie Chart Graph
                      SizedBox(
                        height: 180,
                        child: PieChart(
                          PieChartData(
                            sectionsSpace: 3,
                            centerSpaceRadius: 36,
                            sections: categoryTotals.entries.map((entry) {
                              final catName = entry.key;
                              final amount = entry.value;
                              final pct = totalSpent > 0 ? (amount / totalSpent * 100) : 0;
                              return PieChartSectionData(
                                color: _getCategoryColor(catName),
                                value: amount,
                                title: pct > 5 ? '${pct.toStringAsFixed(0)}%' : '',
                                radius: 42,
                                titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ...categoryTotals.entries.map((entry) {
                        final catName = entry.key;
                        final amount = entry.value;
                        final ratio = (amount / maxCategoryAmount).clamp(0.05, 1.0);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: _getCategoryColor(catName),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(catName, style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13)),
                                    ],
                                  ),
                                  Text(
                                    NumberFormat.currency(symbol: '₹', decimalDigits: 2).format(amount),
                                    style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: ratio,
                                  minHeight: 8,
                                  backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200,
                                  valueColor: AlwaysStoppedAnimation<Color>(_getCategoryColor(catName)),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 3. Category Monthly Budget Tracker & Alerts Card
            Card(
              elevation: isDark ? 3 : 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              color: cardBg,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.track_changes_rounded, color: Colors.blueAccent, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Monthly Category Budgets',
                              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: textColor),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.blueAccent, size: 22),
                          onPressed: () => _showSetBudgetDialog(context, budgets.keys.toList()),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (budgets.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withOpacity(0.04) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'No monthly budgets set yet. Tap + to set budget limits for Food, Fuel, Shopping, etc.!',
                                style: TextStyle(color: subtextColor, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      Builder(builder: (context) {
                        final now = DateTime.now();
                        final totalDaysInMonth = DateTime(_smsMonthFilter.year, _smsMonthFilter.month + 1, 0).day;
                        final isCurrentMonth = _smsMonthFilter.year == now.year && _smsMonthFilter.month == now.month;
                        final daysPassed = isCurrentMonth ? now.day : totalDaysInMonth;
                        final daysRemaining = (totalDaysInMonth - daysPassed + 1).clamp(1, totalDaysInMonth);

                        return Column(
                          children: budgets.entries.map((bEntry) {
                            final cat = bEntry.key;
                            final budgetLimit = bEntry.value;
                            final spent = categoryTotals[cat] ?? 0.0;
                            final isOver = spent > budgetLimit;
                            final percent = budgetLimit > 0 ? (spent / budgetLimit).clamp(0.0, 1.0) : 1.0;

                            final dailyAllowance = budgetLimit > 0 ? (budgetLimit / totalDaysInMonth) : 0.0;
                            final remainingBudget = budgetLimit - spent;
                            final remainingDailyAllowance = (isCurrentMonth && remainingBudget > 0 && daysRemaining > 0)
                                ? (remainingBudget / daysRemaining)
                                : 0.0;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withOpacity(0.03) : Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isOver ? Colors.redAccent : (isDark ? Colors.white12 : Colors.grey.shade200),
                                  width: isOver ? 1.5 : 1.0,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(cat, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14)),
                                      Row(
                                        children: [
                                          Text(
                                            'Spent ₹${spent.toStringAsFixed(0)} / ₹${budgetLimit.toStringAsFixed(0)}',
                                            style: TextStyle(
                                              color: isOver ? Colors.redAccent : subtextColor,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          InkWell(
                                            onTap: () => _showEditSingleBudgetDialog(context, cat, budgetLimit),
                                            child: const Icon(Icons.edit_rounded, size: 16, color: Colors.blueAccent),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: LinearProgressIndicator(
                                      value: percent,
                                      minHeight: 8,
                                      backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200,
                                      valueColor: AlwaysStoppedAnimation<Color>(isOver ? Colors.redAccent : Colors.teal),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.calendar_today_rounded, size: 12, color: Colors.blueAccent),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Daily Budget: ₹${dailyAllowance.toStringAsFixed(0)}/day',
                                            style: TextStyle(color: subtextColor, fontSize: 11, fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                      if (isCurrentMonth && !isOver && remainingDailyAllowance > 0)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.withOpacity(0.12),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            'Rec: ₹${remainingDailyAllowance.toStringAsFixed(0)}/day left',
                                            style: const TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (isOver) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.redAccent),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Exceeded monthly budget limit by ₹${(spent - budgetLimit).toStringAsFixed(0)}!',
                                          style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 4. Monthly Spending Trend Curve Graph (Interactive Spline)
            Card(
              elevation: isDark ? 3 : 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              color: cardBg,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Monthly Spending Trend 📈',
                          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: textColor),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('Interactive Curve', style: TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (dailySpending.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Center(
                          child: Text('No debit activity to map trend curve.', style: TextStyle(color: subtextColor, fontSize: 12)),
                        ),
                      )
                    else
                      SizedBox(
                        height: 150,
                        child: SfCartesianChart(
                          margin: EdgeInsets.zero,
                          plotAreaBorderWidth: 0,
                          primaryXAxis: NumericAxis(
                            majorGridLines: const MajorGridLines(width: 0),
                            axisLine: const AxisLine(width: 0),
                            labelStyle: TextStyle(color: subtextColor, fontSize: 10),
                          ),
                          primaryYAxis: const NumericAxis(isVisible: false),
                          tooltipBehavior: TooltipBehavior(enable: true, header: '', format: 'Day point.x: ₹point.y'),
                          series: <CartesianSeries>[
                            SplineAreaSeries<MapEntry<int, double>, int>(
                              dataSource: dailySpending.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
                              xValueMapper: (MapEntry<int, double> data, _) => data.key,
                              yValueMapper: (MapEntry<int, double> data, _) => data.value,
                              gradient: LinearGradient(
                                colors: [Colors.blueAccent.withOpacity(0.5), Colors.blueAccent.withOpacity(0.0)],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                              borderColor: Colors.blueAccent,
                              borderWidth: 2.5,
                              markerSettings: const MarkerSettings(isVisible: true, width: 4, height: 4, color: Colors.blueAccent),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 5. Daily Expense Bar Chart Distribution
            Card(
              elevation: isDark ? 3 : 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              color: cardBg,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Daily Expense Distribution 📊',
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: textColor),
                    ),
                    const SizedBox(height: 14),
                    if (dailySpending.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Center(
                          child: Text('No daily debit transactions recorded this month.', style: TextStyle(color: subtextColor, fontSize: 12)),
                        ),
                      )
                    else
                      SizedBox(
                        height: 160,
                        child: BarChart(
                          BarChartData(
                            alignment: BarChartAlignment.spaceAround,
                            maxY: (dailySpending.values.isEmpty ? 1.0 : dailySpending.values.reduce((a, b) => a > b ? a : b)) * 1.15,
                            barTouchData: BarTouchData(
                              enabled: true,
                              touchTooltipData: BarTouchTooltipData(
                                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                  final day = group.x.toInt();
                                  final val = rod.toY;
                                  return BarTooltipItem(
                                    'Day $day\n₹${val.toStringAsFixed(0)}',
                                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                                  );
                                },
                              ),
                            ),
                            titlesData: FlTitlesData(
                              show: true,
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (val, meta) {
                                    final int day = val.toInt();
                                    if (day == 1 || day == 5 || day == 10 || day == 15 || day == 20 || day == 25 || day == 30) {
                                      return Text('$day', style: TextStyle(color: subtextColor, fontSize: 10));
                                    }
                                    return const SizedBox.shrink();
                                  },
                                  reservedSize: 20,
                                ),
                              ),
                              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            ),
                            gridData: const FlGridData(show: false),
                            borderData: FlBorderData(show: false),
                            barGroups: List.generate(31, (index) {
                              final day = index + 1;
                              final daySpent = dailySpending[day] ?? 0.0;
                              return BarChartGroupData(
                                x: day,
                                barRods: [
                                  BarChartRodData(
                                    toY: daySpent,
                                    gradient: LinearGradient(
                                      colors: daySpent > 0 ? [Colors.indigoAccent, Colors.blueAccent] : [Colors.grey.withOpacity(0.2), Colors.grey.withOpacity(0.2)],
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                    ),
                                    width: 7,
                                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4)),
                                  ),
                                ],
                              );
                            }),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Color _getCategoryColor(String catName) {
    switch (catName) {
      case 'Food & Dining':
        return Colors.orange;
      case 'Fuel & Travel':
        return Colors.redAccent;
      case 'Groceries':
        return Colors.green;
      case 'Bills & Utilities':
        return Colors.blue;
      case 'Shopping':
        return Colors.purple;
      case 'Personal Transfer':
        return Colors.purpleAccent;
      case 'Self Transfer':
        return Colors.indigoAccent;
      case 'Borrowed':
        return Colors.amber.shade700;
      case 'Borrowed Repaid':
        return Colors.orange.shade700;
      case 'Lended':
        return Colors.teal;
      case 'Loan Repaid':
        return Colors.green.shade700;
      case 'Entertainment':
        return Colors.pink;
      case 'Medical & Health':
        return Colors.redAccent;
      default:
        return Colors.blueAccent;
    }
  }

  void _showSetBudgetDialog(BuildContext context, List<String> existingBudgetCats) {
    String selectedCategory = 'Food & Dining';
    final amountController = TextEditingController();
    final customCategoryController = TextEditingController();

    final List<String> availableCategories = [
      'Food & Dining',
      'Fuel & Travel',
      'Groceries',
      'Bills & Utilities',
      'Shopping',
      'Personal Transfer',
      'Entertainment',
      'Medical & Health',
      'Others',
    ];

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.track_changes_rounded, color: Colors.blueAccent),
              SizedBox(width: 8),
              Text('Set Monthly Budget'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedCategory,
                decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                items: availableCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedCategory = val);
                },
              ),
              if (selectedCategory == 'Others') ...[
                const SizedBox(height: 14),
                TextField(
                  controller: customCategoryController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Custom Budget Name',
                    hintText: 'e.g. Subscriptions, Gaming, Gifts',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.edit_note_rounded),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Monthly Limit (₹)',
                  hintText: 'e.g. 5000',
                  border: OutlineInputBorder(),
                  prefixText: '₹ ',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
              onPressed: () async {
                final amt = double.tryParse(amountController.text.trim()) ?? 0.0;
                String categoryToSave = selectedCategory;
                if (selectedCategory == 'Others') {
                  final customName = customCategoryController.text.trim();
                  if (customName.isNotEmpty) {
                    categoryToSave = customName;
                  }
                }

                if (amt > 0) {
                  await _financeService.saveCategoryBudget(categoryToSave, amt);
                  if (dialogCtx.mounted) {
                    Navigator.pop(dialogCtx);
                    _keepAnalyticsTabActive();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Budget of ₹${amt.toStringAsFixed(0)} set for $categoryToSave!'), backgroundColor: Colors.green),
                    );
                  }
                }
              },
              child: const Text('Save Budget'),
            ),
          ],
        ),
      ),
    );
  }

  void _keepAnalyticsTabActive() {
    _smsSubTabNotifier.value = 1;
    if (_smsPageController.hasClients && _smsPageController.page?.round() != 1) {
      _smsPageController.jumpToPage(1);
    }
  }

  void _showEditSingleBudgetDialog(BuildContext context, String category, double currentLimit) {
    final amountController = TextEditingController(text: currentLimit.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Edit Budget: $category'),
        content: TextField(
          controller: amountController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Monthly Limit (₹)',
            border: OutlineInputBorder(),
            prefixText: '₹ ',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await _financeService.saveCategoryBudget(category, 0);
              if (dialogCtx.mounted) {
                Navigator.pop(dialogCtx);
                _keepAnalyticsTabActive();
              }
            },
            child: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
            onPressed: () async {
              final amt = double.tryParse(amountController.text.trim()) ?? 0.0;
              await _financeService.saveCategoryBudget(category, amt);
              if (dialogCtx.mounted) {
                Navigator.pop(dialogCtx);
                _keepAnalyticsTabActive();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCustomHeaderRulesDialog(BuildContext context) async {
    final patternController = TextEditingController();
    final bankNameController = TextEditingController();
    String? selectedPopularBank;

    final popularBanks = [
      'Indian Bank',
      'HDFC Bank',
      'SBI',
      'ICICI Bank',
      'Axis Bank',
      'Kotak Bank',
      'Bank of Baroda',
      'Canara Bank',
      'Union Bank',
      'PNB',
      'IDFC FIRST Bank',
      'IndusInd Bank',
      'YES Bank',
      'Federal Bank',
      'Paytm Bank',
      'PhonePe',
      'Google Pay',
    ];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final bg = isDark ? const Color(0xFF1E293B) : Colors.white;
        final textColor = isDark ? Colors.white : Colors.black87;
        final subtextColor = isDark ? Colors.white70 : Colors.grey.shade600;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.settings_suggest_rounded, color: Colors.blueAccent, size: 24),
                            const SizedBox(width: 8),
                            Text(
                              'Bank Header Rules ⚙️',
                              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    Text(
                      'Define custom keyword rules to auto-map SMS sender headers to banks (e.g. keyword "INDBNK" → "Indian Bank").',
                      style: TextStyle(fontSize: 12, color: subtextColor),
                    ),
                    const SizedBox(height: 16),

                    // ADD NEW RULE FORM
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : Colors.blue.shade50.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Add New Rule ➕', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                          const SizedBox(height: 10),
                          TextField(
                            controller: patternController,
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              labelText: 'SMS Header Keyword / Pattern',
                              hintText: 'e.g. INDBNK, SBI, BOB',
                              prefixIcon: const Icon(Icons.title_rounded, size: 20),
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: selectedPopularBank,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: 'Select Bank',
                                    prefixIcon: const Icon(Icons.account_balance_rounded, size: 20),
                                    isDense: true,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  items: popularBanks.map((b) => DropdownMenuItem(value: b, child: Text(b, style: const TextStyle(fontSize: 13)))).toList(),
                                  onChanged: (val) {
                                    setSheetState(() {
                                      selectedPopularBank = val;
                                      if (val != null) {
                                        bankNameController.text = val;
                                      }
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: bankNameController,
                            decoration: InputDecoration(
                              labelText: 'Or Custom Bank Name',
                              hintText: 'e.g. Indian Bank, My Co-op Bank',
                              prefixIcon: const Icon(Icons.edit_note_rounded, size: 20),
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: () async {
                              final p = patternController.text.trim();
                              final b = bankNameController.text.trim();
                              if (p.isEmpty || b.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Please enter both pattern keyword and bank name')),
                                );
                                return;
                              }

                              await _financeService.addCustomHeaderBankRule(p, b);
                              patternController.clear();
                              bankNameController.clear();
                              setSheetState(() {
                                selectedPopularBank = null;
                              });

                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Rule saved for "$p" → "$b"'), backgroundColor: Colors.green),
                                );
                              }
                            },
                            icon: const Icon(Icons.save_rounded, size: 18),
                            label: const Text('Save Header Rule', style: TextStyle(fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                    Text('Active Rules List 📋', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: textColor)),
                    const SizedBox(height: 8),

                    // LIST OF EXISTING RULES
                    Expanded(
                      child: StreamBuilder<List<Map<String, String>>>(
                        stream: _financeService.getCustomHeaderBankRulesStream(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }

                          final rules = snapshot.data ?? [];
                          if (rules.isEmpty) {
                            return Center(
                              child: Text(
                                'No custom bank rules defined yet.\nAdd a rule above to map SMS headers.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: subtextColor, fontSize: 13),
                              ),
                            );
                          }

                          return ListView.builder(
                            itemCount: rules.length,
                            itemBuilder: (ctx, index) {
                              final rule = rules[index];
                              final p = rule['pattern'] ?? '';
                              final b = rule['bankName'] ?? '';

                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                color: isDark ? const Color(0xFF0F172A) : Colors.grey.shade100,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: ListTile(
                                  dense: true,
                                  title: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.blueAccent.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          p,
                                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent, fontSize: 12),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.arrow_forward_rounded, size: 14, color: Colors.grey),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          b,
                                          style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 13),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                    onPressed: () async {
                                      await _financeService.deleteCustomHeaderBankRule(p);
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Deleted rule for "$p"')),
                                        );
                                      }
                                    },
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ============================================================================
// GROUP EVENT DETAIL SCREEN (WHO OWES WHOM & EXPENSES)
// ============================================================================

class GroupEventDetailScreen extends StatefulWidget {
  final GroupEvent group;
  const GroupEventDetailScreen({super.key, required this.group});

  @override
  State<GroupEventDetailScreen> createState() => _GroupEventDetailScreenState();
}

class _GroupEventDetailScreenState extends State<GroupEventDetailScreen> {
  final FinanceService _financeService = FinanceService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.group.title),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddExpenseDialog(context),
        icon: const Icon(Icons.receipt),
        label: const Text('Add Expense'),
      ),
      body: StreamBuilder<List<GroupExpense>>(
        stream: _financeService.getGroupExpensesStream(widget.group.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final expenses = snapshot.data ?? [];
          final settlements = _financeService.calculateGroupBalances(widget.group.members, expenses);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Members list
              Wrap(
                spacing: 8,
                children: widget.group.members
                    .map((m) => Chip(
                          avatar: CircleAvatar(child: Text(m[0].toUpperCase())),
                          label: Text(m),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),

              // Settlement Matrix (Who Owes Whom)
              Card(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.swap_horiz, color: Colors.orange),
                          SizedBox(width: 8),
                          Text('Settlement Matrix (Who Owes Whom)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (settlements.isEmpty)
                        const Text('All settled up! No pending balances in this group.')
                      else
                        Column(
                          children: settlements
                              .map((s) => Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '${s.fromPerson} owes ${s.toPerson}',
                                          style: const TextStyle(fontWeight: FontWeight.w600),
                                        ),
                                        Text(
                                          '₹${NumberFormat('#,##,##0.00').format(s.amount)}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold, color: Colors.orange),
                                        ),
                                      ],
                                    ),
                                  ))
                              .toList(),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              const Text('Expenses Log', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),

              if (expenses.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: Text('No group expenses added yet.')),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: expenses.length,
                  itemBuilder: (context, index) {
                    final exp = expenses[index];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(exp.description, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          'Paid by ${exp.payerName} • Split among ${exp.involvedMembers.join(", ")}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '₹${NumberFormat('#,##,##0').format(exp.amount)}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.grey),
                              onPressed: () => _financeService.deleteGroupExpense(exp.id),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  void _showAddExpenseDialog(BuildContext context) {
    final descCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String payer = widget.group.members.first;
    final Set<String> selectedInvolved = Set.from(widget.group.members);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Group Expense'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Expense Description (e.g. Dinner, Fuel)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Total Amount (₹)'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: payer,
                  decoration: const InputDecoration(labelText: 'Paid By'),
                  items: widget.group.members
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (val) => payer = val!,
                ),
                const SizedBox(height: 12),
                const Text('Split Among:', style: TextStyle(fontWeight: FontWeight.bold)),
                ...widget.group.members.map(
                  (m) => CheckboxListTile(
                    title: Text(m),
                    value: selectedInvolved.contains(m),
                    onChanged: (checked) {
                      setDialogState(() {
                        if (checked == true) {
                          selectedInvolved.add(m);
                        } else {
                          selectedInvolved.remove(m);
                        }
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (descCtrl.text.trim().isEmpty) return;
                final amt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                if (amt <= 0 || selectedInvolved.isEmpty) return;

                _financeService.addGroupExpense(GroupExpense(
                  id: '',
                  groupId: widget.group.id,
                  description: descCtrl.text.trim(),
                  amount: amt,
                  payerName: payer,
                  involvedMembers: selectedInvolved.toList(),
                  date: DateTime.now(),
                ));
                Navigator.pop(context);
              },
              child: const Text('Add Expense'),
            ),
          ],
        ),
      ),
    );
  }
}

