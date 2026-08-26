import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bank_account.dart';
import '../models/debt_record.dart';
import '../models/sms_transaction.dart';
import '../services/finance_service.dart';

class NightlyExpenseTagSheet extends StatefulWidget {
  final List<SmsTransaction> pendingTransactions;

  const NightlyExpenseTagSheet({super.key, required this.pendingTransactions});

  @override
  State<NightlyExpenseTagSheet> createState() => _NightlyExpenseTagSheetState();
}

class _NightlyExpenseTagSheetState extends State<NightlyExpenseTagSheet> {
  late List<SmsTransaction> _items;
  final Map<String, String> _selectedCategories = {};
  final Map<String, TextEditingController> _noteControllers = {};
  final Map<String, String> _targetBankIds = {};
  final Map<String, String> _targetDebtIds = {};
  final Map<String, String> _selectedBankNames = {};
  List<String> _customTagRecommendations = [];

  final List<Map<String, dynamic>> _categories = [
    {'name': 'Food & Dining', 'icon': Icons.fastfood, 'color': Colors.orange},
    {'name': 'Fuel & Travel', 'icon': Icons.local_gas_station, 'color': Colors.redAccent},
    {'name': 'Groceries', 'icon': Icons.shopping_basket, 'color': Colors.green},
    {'name': 'Bills & Utilities', 'icon': Icons.receipt_long, 'color': Colors.blue},
    {'name': 'Shopping', 'icon': Icons.shopping_bag, 'color': Colors.purple},
    {'name': 'Self Transfer', 'icon': Icons.swap_horiz_rounded, 'color': Colors.indigoAccent},
    {'name': 'Borrowed', 'icon': Icons.south_west_rounded, 'color': Colors.amber.shade700},
    {'name': 'Lended', 'icon': Icons.north_east_rounded, 'color': Colors.teal},
    {'name': 'Loan Repaid', 'icon': Icons.task_alt_rounded, 'color': Colors.green.shade700},
    {'name': 'Entertainment', 'icon': Icons.movie, 'color': Colors.pink},
    {'name': 'Personal Care', 'icon': Icons.spa, 'color': Colors.deepOrangeAccent},
    {'name': 'Ignored / Not Needed', 'icon': Icons.block_rounded, 'color': Colors.blueGrey},
    {'name': 'Others', 'icon': Icons.more_horiz, 'color': Colors.grey},
  ];

  StreamSubscription<List<String>>? _customTagsSub;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.pendingTransactions);
    for (var tx in _items) {
      _selectedCategories[tx.id] = tx.category == 'Uncategorized' ? 'Food & Dining' : tx.category;
      _noteControllers[tx.id] = TextEditingController(text: '');
      _selectedBankNames[tx.id] = tx.bankName;
    }
    _customTagsSub = FinanceService().getUserCustomTagsStream().listen((tags) {
      if (mounted) {
        setState(() {
          _customTagRecommendations = tags;
        });
      }
    });
  }

  @override
  void dispose() {
    _customTagsSub?.cancel();
    for (var ctrl in _noteControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _verifyAndSyncAll() async {
    final finance = FinanceService();
    for (var tx in _items) {
      final category = _selectedCategories[tx.id] ?? 'Others';
      final notes = _noteControllers[tx.id]?.text.trim() ?? '';
      final chosenBankName = _selectedBankNames[tx.id] ?? tx.bankName;
      
      if (notes.isNotEmpty) {
        await finance.saveUserCustomTag(notes);
      }

      final updatedTx = tx.copyWith(
        isVerified: true,
        bankName: chosenBankName,
        category: category,
        notes: notes.isNotEmpty ? notes : tx.payee,
      );

      final destBankId = _targetBankIds[tx.id];
      await finance.updateSmsTransaction(updatedTx, destinationBankAccountId: destBankId);

      // If category is Loan Repaid, mark target debt as settled!
      if (category == 'Loan Repaid') {
        final debtId = _targetDebtIds[tx.id];
        if (debtId != null && debtId.isNotEmpty) {
          await finance.settleDebtById(debtId);
        }
      }
    }

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Synced ${_items.length} expenses to your bank balances!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final Color cardColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final Color textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color subtextColor = isDark ? Colors.white70 : Colors.black54;
    final Color borderColor = isDark ? Colors.white12 : Colors.grey.shade300;
    final Color inputBg = isDark ? const Color(0xFF1E293B) : Colors.grey.shade100;
    final Color chipBg = isDark ? const Color(0xFF1E293B) : Colors.grey.shade200;

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.grey.shade400,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.receipt_long_rounded, color: Colors.amber, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Expense Review',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    Text(
                      '${_items.length} untagged bank transactions detected',
                      style: TextStyle(color: subtextColor, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Expanded(
            child: ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final tx = _items[index];
                final isDebit = tx.type == 'Debit';
                final selectedCat = _selectedCategories[tx.id] ?? 'Others';
                final currentBankName = _selectedBankNames[tx.id] ?? tx.bankName;
                final bool isUnassignedBank = currentBankName == 'Bank' || currentBankName.toLowerCase() == 'unknown';

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isUnassignedBank ? Colors.redAccent : borderColor,
                      width: isUnassignedBank ? 1.8 : 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isDebit ? Icons.arrow_upward : Icons.arrow_downward,
                                color: isDebit ? Colors.redAccent : Colors.greenAccent,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                currentBankName,
                                style: TextStyle(
                                  color: isUnassignedBank ? Colors.redAccent : textColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              if (tx.accountLast4.isNotEmpty) ...[
                                const SizedBox(width: 4),
                                Text(
                                  '(*${tx.accountLast4})',
                                  style: TextStyle(color: subtextColor, fontSize: 12),
                                ),
                              ],
                              if (isUnassignedBank) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text('⚠️ Assign Bank', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                              ],
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () => _showSmsDetailsDialog(context, tx),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                            ],
                          ),
                          Text(
                            '${isDebit ? '-' : '+'}${NumberFormat.currency(symbol: '₹', decimalDigits: 2).format(tx.amount)}',
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDebit ? Colors.redAccent : Colors.green,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      Text(
                        'Payee: ${tx.payee}',
                        style: TextStyle(color: subtextColor, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),

                      // Bank Account Selector / Reassigner
                      StreamBuilder<List<BankAccount>>(
                        stream: FinanceService().getAccountsStream(),
                        builder: (context, accountsSnap) {
                          final userAccounts = accountsSnap.data ?? [];
                          if (userAccounts.isEmpty) return const SizedBox();

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                            decoration: BoxDecoration(
                              color: isUnassignedBank ? Colors.red.withOpacity(0.12) : inputBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isUnassignedBank ? Colors.redAccent.withOpacity(0.6) : borderColor,
                                width: isUnassignedBank ? 1.2 : 0.8,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isUnassignedBank ? Icons.warning_amber_rounded : Icons.account_balance_rounded,
                                  size: 15,
                                  color: isUnassignedBank ? Colors.redAccent : Colors.blueAccent,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: userAccounts.any((a) => a.name == currentBankName)
                                          ? currentBankName
                                          : null,
                                      hint: Text(
                                        isUnassignedBank ? '⚠️ Assign Bank Account (Select)' : 'Change Bank Account',
                                        style: TextStyle(
                                          color: isUnassignedBank ? Colors.redAccent : subtextColor,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      isExpanded: true,
                                      dropdownColor: bgColor,
                                      style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600),
                                      items: userAccounts.map((acc) {
                                        return DropdownMenuItem<String>(
                                          value: acc.name,
                                          child: Text('${acc.name} (Bal: ₹${acc.currentBalance.toStringAsFixed(0)})'),
                                        );
                                      }).toList(),
                                      onChanged: (newBankName) {
                                        if (newBankName != null) {
                                          final selectedAcc = userAccounts.firstWhere((a) => a.name == newBankName);
                                          setState(() {
                                            _selectedBankNames[tx.id] = newBankName;
                                            _targetBankIds[tx.id] = selectedAcc.id;
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      Text(
                        DateFormat('dd MMM yyyy, hh:mm a').format(tx.timestamp),
                        style: TextStyle(color: isDark ? Colors.grey : Colors.grey.shade600, fontSize: 11),
                      ),
                      const SizedBox(height: 14),

                      // Category Selector Chips
                      Text(
                        'Select Category:',
                        style: TextStyle(color: subtextColor, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),

                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _categories.map((cat) {
                          final bool isSelected = selectedCat == cat['name'];
                          final Color catColor = cat['color'] as Color;

                          return ChoiceChip(
                            avatar: Icon(cat['icon'] as IconData, size: 16, color: isSelected ? Colors.white : catColor),
                            label: Text(
                              cat['name'] as String,
                              style: TextStyle(
                                color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: catColor,
                            backgroundColor: chipBg,
                            onSelected: (selected) {
                              if (selected) {
                                setState(() {
                                  _selectedCategories[tx.id] = cat['name'] as String;
                                });
                              }
                            },
                          );
                        }).toList(),
                      ),

                      if (selectedCat == 'Self Transfer') ...[
                        const SizedBox(height: 12),
                        StreamBuilder<List<BankAccount>>(
                          stream: FinanceService().getAccountsStream(),
                          builder: (context, accountsSnap) {
                            final accounts = accountsSnap.data ?? [];
                            if (accounts.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Text('No Bank Accounts added yet. Add banks in Accounts tab!', style: TextStyle(color: Colors.amber, fontSize: 12)),
                              );
                            }

                            final currentTargetId = _targetBankIds[tx.id] ?? accounts.first.id;

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: inputBg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.indigoAccent),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Select Destination Bank Account:',
                                    style: TextStyle(color: Colors.indigoAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  DropdownButton<String>(
                                    value: accounts.any((a) => a.id == currentTargetId) ? currentTargetId : accounts.first.id,
                                    isExpanded: true,
                                    dropdownColor: bgColor,
                                    style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600),
                                    underline: const SizedBox(),
                                    items: accounts.map((acc) {
                                      return DropdownMenuItem<String>(
                                        value: acc.id,
                                        child: Text('${acc.name} (Bal: ₹${acc.currentBalance.toStringAsFixed(0)})'),
                                      );
                                    }).toList(),
                                    onChanged: (newId) {
                                      if (newId != null) {
                                        setState(() {
                                          _targetBankIds[tx.id] = newId;
                                        });
                                      }
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                      if (selectedCat == 'Loan Repaid') ...[
                        const SizedBox(height: 12),
                        StreamBuilder<List<DebtRecord>>(
                          stream: FinanceService().getDebtsStream(),
                          builder: (context, debtsSnap) {
                            final activeDebts = (debtsSnap.data ?? []).where((d) => !d.isSettled).toList();
                            if (activeDebts.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Text('No active pending debts found to settle.', style: TextStyle(color: Colors.amber, fontSize: 12)),
                              );
                            }

                            final currentDebtId = _targetDebtIds[tx.id] ?? activeDebts.first.id;

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: inputBg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.green.shade600),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Select Pending Debt/Loan to Settle:',
                                    style: TextStyle(color: Colors.green.shade600, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  DropdownButton<String>(
                                    value: activeDebts.any((d) => d.id == currentDebtId) ? currentDebtId : activeDebts.first.id,
                                    isExpanded: true,
                                    dropdownColor: bgColor,
                                    style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600),
                                    underline: const SizedBox(),
                                    items: activeDebts.map((d) {
                                      final label = d.type == 'lent'
                                          ? '${d.personName} owes me ₹${d.amount.toStringAsFixed(0)}'
                                          : 'I owe ${d.personName} ₹${d.amount.toStringAsFixed(0)}';
                                      return DropdownMenuItem<String>(
                                        value: d.id,
                                        child: Text(label),
                                      );
                                    }).toList(),
                                    onChanged: (newId) {
                                      if (newId != null) {
                                        setState(() {
                                          _targetDebtIds[tx.id] = newId;
                                        });
                                      }
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                      if (selectedCat == 'Others') ...[
                        const SizedBox(height: 12),
                        Builder(
                          builder: (context) {
                            final currentInput = _noteControllers[tx.id]?.text.trim() ?? '';
                            List<String> matchingTags = [];
                            if (currentInput.isEmpty) {
                              matchingTags = _customTagRecommendations.take(5).toList();
                            } else {
                              matchingTags = _customTagRecommendations
                                  .where((t) => t.toLowerCase().contains(currentInput.toLowerCase()))
                                  .take(5)
                                  .toList();
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (matchingTags.isNotEmpty) ...[
                                  Text(
                                    currentInput.isEmpty ? 'Your Custom Tags (Tap to fill):' : 'Matching Custom Tags:',
                                    style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: matchingTags.map((tag) {
                                      return ActionChip(
                                        backgroundColor: chipBg,
                                        side: const BorderSide(color: Colors.amber, width: 0.8),
                                        avatar: const Icon(Icons.bolt, size: 14, color: Colors.amber),
                                        label: Text(tag, style: TextStyle(color: textColor, fontSize: 11)),
                                        onPressed: () {
                                          setState(() {
                                            _noteControllers[tx.id]?.text = tag;
                                            _noteControllers[tx.id]?.selection = TextSelection.fromPosition(
                                              TextPosition(offset: tag.length),
                                            );
                                          });
                                        },
                                      );
                                    }).toList(),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                TextField(
                                  controller: _noteControllers[tx.id],
                                  onChanged: (_) {
                                    setState(() {});
                                  },
                                  style: TextStyle(color: textColor, fontSize: 13),
                                  decoration: InputDecoration(
                                    hintText: 'Type custom reason (e.g., Domain, Gift, Bike repair)...',
                                    hintStyle: TextStyle(color: subtextColor, fontSize: 12),
                                    filled: true,
                                    fillColor: inputBg,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: borderColor),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.check_circle_outline, color: Colors.white),
              label: Text(
                'CONFIRM & SYNC BALANCES (${_items.length})',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _verifyAndSyncAll,
            ),
          ),
        ],
      ),
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
}
