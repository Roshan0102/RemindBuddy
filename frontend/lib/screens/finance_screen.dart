import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  int? _selectedFeatureIndex;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
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
        return const Text('Auto SMS Tracker 📱', style: TextStyle(fontWeight: FontWeight.bold));
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
        'title': 'Auto SMS Tracker 📱',
        'subtitle': 'Real-time bank SMS parsing, monthly spend analytics & 1-tap review',
        'icon': Icons.sms_rounded,
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
                else if (accounts.length <= 3)
                  Row(
                    children: accounts.map((acc) {
                      final Color accColor = Color(acc.colorHex);
                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          height: 90,
                          child: Card(
                            elevation: 2,
                            margin: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: accColor.withOpacity(0.4), width: 1.5),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Icon(_getIconData(acc.iconName), color: accColor, size: 18),
                                      PopupMenuButton<String>(
                                        padding: EdgeInsets.zero,
                                        iconSize: 16,
                                        onSelected: (val) {
                                          if (val == 'delete') {
                                            _financeService.deleteAccount(acc.id);
                                          }
                                        },
                                        itemBuilder: (_) => [
                                          const PopupMenuItem(value: 'delete', child: Text('Delete Account')),
                                        ],
                                        icon: const Icon(Icons.more_vert, size: 16, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    acc.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '₹${NumberFormat('#,##,##0').format(acc.currentBalance)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: acc.currentBalance >= 0 ? Colors.green.shade700 : Colors.red,
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
                    }).toList(),
                  )
                else
                  SizedBox(
                    height: 90,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: accounts.length,
                      itemBuilder: (context, index) {
                        final acc = accounts[index];
                        final Color accColor = Color(acc.colorHex);

                        return Container(
                          width: 115,
                          margin: const EdgeInsets.only(right: 8),
                          child: Card(
                            elevation: 2,
                            margin: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: accColor.withOpacity(0.4), width: 1.5),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Icon(_getIconData(acc.iconName), color: accColor, size: 18),
                                      PopupMenuButton<String>(
                                        padding: EdgeInsets.zero,
                                        iconSize: 16,
                                        onSelected: (val) {
                                          if (val == 'delete') {
                                            _financeService.deleteAccount(acc.id);
                                          }
                                        },
                                        itemBuilder: (_) => [
                                          const PopupMenuItem(value: 'delete', child: Text('Delete Account')),
                                        ],
                                        icon: const Icon(Icons.more_vert, size: 16, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    acc.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '₹${NumberFormat('#,##,##0').format(acc.currentBalance)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: acc.currentBalance >= 0 ? Colors.green.shade700 : Colors.red,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
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
                            Switch(
                              value: bill.isActive,
                              onChanged: (val) {
                                _financeService.updateBill(RecurringBill(
                                  id: bill.id,
                                  title: bill.title,
                                  amount: bill.amount,
                                  category: bill.category,
                                  dueDate: bill.dueDate,
                                  frequency: bill.frequency,
                                  accountId: bill.accountId,
                                  isActive: val,
                                  notes: bill.notes,
                                ));
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _financeService.deleteBill(bill.id),
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
    final noteCtrl = TextEditingController();
    String selectedAccountId = accounts.first.id;
    String type = 'expense';
    String category = 'General';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Transaction'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                      .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                      .toList(),
                  onChanged: (val) => selectedAccountId = val!,
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
                  decoration: const InputDecoration(labelText: 'Note / Reason (e.g., Dad gave money, Gas bill)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final amt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                if (amt <= 0) return;

                _financeService.addTransaction(FinanceTransaction(
                  id: '',
                  accountId: selectedAccountId,
                  type: type,
                  amount: amt,
                  category: category,
                  note: noteCtrl.text.trim(),
                  timestamp: DateTime.now(),
                ));
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddBillDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final customDaysCtrl = TextEditingController(text: '15');
    DateTime dueDate = DateTime.now().add(const Duration(days: 7));
    String selectedFrequency = 'monthly';
    String category = 'Utilities';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Recurring Bill / Subscription'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                const SizedBox(height: 12),
                ListTile(
                  title: Text('Due Date: ${DateFormat('MMM d, yyyy').format(dueDate)}'),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: dueDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                    );
                    if (picked != null) {
                      setDialogState(() => dueDate = picked);
                    }
                  },
                ),
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
                  ),
                ],
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

                _financeService.addBill(RecurringBill(
                  id: '',
                  title: titleCtrl.text.trim(),
                  amount: amt,
                  category: category,
                  dueDate: dueDate,
                  frequency: freqStr,
                  notes: notesCtrl.text.trim(),
                ));
                Navigator.pop(context);
              },
              child: const Text('Add Bill'),
            ),
          ],
        ),
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

            final allTransactions = snapshot.data ?? [];

            final monthTransactions = allTransactions.where((tx) {
              return tx.timestamp.year == _smsMonthFilter.year && tx.timestamp.month == _smsMonthFilter.month;
            }).toList();

            final pendingUntagged = allTransactions.where((t) => !t.isVerified).toList();

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

            return ListView(
              padding: const EdgeInsets.all(16),
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
                  const SizedBox(height: 14),
                ],

                // Month Selector Bar with Sync & Month Delete Actions
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
                const SizedBox(height: 14),

            // Monthly Financial Summary & Spending Graph Card
            Card(
              elevation: isDark ? 4 : 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              color: summaryBg,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Total Spent', style: TextStyle(color: subtextColor, fontSize: 12)),
                            Text(
                              NumberFormat.currency(symbol: '₹', decimalDigits: 2).format(totalSpent),
                              style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.redAccent),
                            ),
                          ],
                        ),
                        Container(width: 1, height: 35, color: isDark ? Colors.white12 : Colors.black12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Total Received', style: TextStyle(color: subtextColor, fontSize: 12)),
                            Text(
                              NumberFormat.currency(symbol: '₹', decimalDigits: 2).format(totalReceived),
                              style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green),
                            ),
                          ],
                        ),
                      ],
                    ),

                    if (categoryTotals.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Spending Breakdown by Category',
                        style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 10),
                      ...categoryTotals.entries.map((entry) {
                        final double percentage = totalSpent > 0 ? (entry.value / totalSpent) : 0.0;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(entry.key, style: TextStyle(color: textColor, fontSize: 12)),
                                  Text(
                                    NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(entry.value),
                                    style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: percentage.clamp(0.0, 1.0),
                                  minHeight: 6,
                                  backgroundColor: isDark ? Colors.white10 : Colors.black12,
                                  color: Colors.blueAccent,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Pending Review Banner
            if (pendingUntagged.isNotEmpty) ...[
              Card(
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
              const SizedBox(height: 14),
            ],

            // Section Header
            Text(
              '${DateFormat('MMMM').format(_smsMonthFilter)} Transactions (${monthTransactions.length})',
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: textColor),
            ),
            const SizedBox(height: 10),

            if (monthTransactions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    'No SMS bank transactions recorded for ${DateFormat('MMMM yyyy').format(_smsMonthFilter)}.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: subtextColor),
                  ),
                ),
              )
            else
              ...monthTransactions.map((tx) {
                final isDebit = tx.type == 'Debit';
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  color: cardBg,
                  elevation: isDark ? 2 : 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                  ),
                  child: ListTile(
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (ctx) => NightlyExpenseTagSheet(pendingTransactions: [tx]),
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
                        Text(
                          tx.bankName,
                          style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14),
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
                  ),
                );
              }).toList(),
          ],
        );
      },
    );
  },
);
}

  void _showSmsSyncDialog() {
    final String currentMonthName = DateFormat('MMMM').format(_smsMonthFilter);
    final now = DateTime.now();
    int daysInCurrentMonth = now.day;
    if (_smsMonthFilter.year != now.year || _smsMonthFilter.month != now.month) {
      daysInCurrentMonth = DateTime(_smsMonthFilter.year, _smsMonthFilter.month + 1, 0).day;
    }

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
                title: Text('Current Selected Month ($currentMonthName)'),
                subtitle: Text('Scan past $daysInCurrentMonth days of SMS'),
                onTap: () {
                  Navigator.pop(ctx);
                  _runSmsScan(daysInCurrentMonth);
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

  Future<void> _runSmsScan(int days) async {
    setState(() => _isScanningInbox = true);
    final count = await _financeService.scanPastSmsInbox(days: days);
    setState(() => _isScanningInbox = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(count > 0 ? 'Detected & saved $count new SMS transactions!' : 'No new bank SMS detected in past $days days.'),
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
