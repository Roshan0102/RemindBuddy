import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bank_account.dart';
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
  List<String> _customTagRecommendations = ['Water Can', 'Milk', 'House Maid', 'Laundry', 'WiFi Bill'];

  final List<Map<String, dynamic>> _categories = [
    {'name': 'Food & Dining', 'icon': Icons.fastfood, 'color': Colors.orange},
    {'name': 'Fuel & Travel', 'icon': Icons.local_gas_station, 'color': Colors.redAccent},
    {'name': 'Groceries', 'icon': Icons.shopping_basket, 'color': Colors.green},
    {'name': 'Bills & Utilities', 'icon': Icons.receipt_long, 'color': Colors.blue},
    {'name': 'Shopping', 'icon': Icons.shopping_bag, 'color': Colors.purple},
    {'name': 'Self Transfer', 'icon': Icons.swap_horiz_rounded, 'color': Colors.indigoAccent},
    {'name': 'Entertainment', 'icon': Icons.movie, 'color': Colors.pink},
    {'name': 'Personal Care', 'icon': Icons.spa, 'color': Colors.teal},
    {'name': 'Ignored / Not Needed', 'icon': Icons.block_rounded, 'color': Colors.blueGrey},
    {'name': 'Others', 'icon': Icons.more_horiz, 'color': Colors.grey},
  ];

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.pendingTransactions);
    for (var tx in _items) {
      _selectedCategories[tx.id] = tx.category == 'Uncategorized' ? 'Food & Dining' : tx.category;
      _noteControllers[tx.id] = TextEditingController(text: tx.notes == tx.payee ? '' : tx.notes);
    }
    _loadCustomTagRecommendations();
  }

  Future<void> _loadCustomTagRecommendations() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('user_custom_tags');
    if (saved != null && saved.isNotEmpty) {
      setState(() {
        for (var s in saved) {
          if (!_customTagRecommendations.contains(s)) {
            _customTagRecommendations.insert(0, s);
          }
        }
      });
    }
  }

  Future<void> _saveCustomTag(String tag) async {
    if (tag.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final clean = tag.trim();
    if (!_customTagRecommendations.contains(clean)) {
      _customTagRecommendations.insert(0, clean);
      await prefs.setStringList('user_custom_tags', _customTagRecommendations);
    }
  }

  Future<void> _verifyAndSyncAll() async {
    final finance = FinanceService();
    for (var tx in _items) {
      final category = _selectedCategories[tx.id] ?? 'Others';
      final notes = _noteControllers[tx.id]?.text ?? '';
      
      if (notes.isNotEmpty) {
        await _saveCustomTag(notes);
      }

      final updatedTx = tx.copyWith(
        isVerified: true,
        category: category,
        notes: notes.isNotEmpty ? notes : tx.payee,
      );

      final destBankId = _targetBankIds[tx.id];
      await finance.updateSmsTransaction(updatedTx, destinationBankAccountId: destBankId);
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
    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                color: Colors.white24,
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
                child: const Icon(Icons.nightlight_round, color: Colors.amber, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nightly Expense Review 🌙',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '${_items.length} untagged bank transactions detected',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
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

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
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
                                tx.bankName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              if (tx.accountLast4.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '(*${tx.accountLast4})',
                                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            '${isDebit ? '-' : '+'}${NumberFormat.currency(symbol: '₹', decimalDigits: 2).format(tx.amount)}',
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDebit ? Colors.redAccent : Colors.greenAccent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      Text(
                        'Payee: ${tx.payee}',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      Text(
                        DateFormat('dd MMM yyyy, hh:mm a').format(tx.timestamp),
                        style: const TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                      const SizedBox(height: 14),

                      // Category Selector Chips
                      const Text(
                        'Select Category:',
                        style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600),
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
                                color: isSelected ? Colors.white : Colors.white70,
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: catColor,
                            backgroundColor: const Color(0xFF1E293B),
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
                                color: const Color(0xFF1E293B),
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
                                    dropdownColor: const Color(0xFF1E293B),
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
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
                      if (selectedCat == 'Others') ...[
                        const SizedBox(height: 12),
                        if (_customTagRecommendations.isNotEmpty) ...[
                          const Text(
                            'Frequent Custom Tags (Tap to fill):',
                            style: TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: _customTagRecommendations.take(6).map((tag) {
                              return ActionChip(
                                backgroundColor: const Color(0xFF1E293B),
                                side: const BorderSide(color: Colors.amber, width: 0.8),
                                avatar: const Icon(Icons.bolt, size: 14, color: Colors.amber),
                                label: Text(tag, style: const TextStyle(color: Colors.white, fontSize: 11)),
                                onPressed: () {
                                  setState(() {
                                    _noteControllers[tx.id]?.text = tag;
                                  });
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 10),
                        ],
                        TextField(
                          controller: _noteControllers[tx.id],
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Type custom reason (e.g., Domain, Gift, Bike repair)...',
                            hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                            filled: true,
                            fillColor: const Color(0xFF1E293B),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.white24),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
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
}
