import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/gold_price.dart';

class GoldChitTrackerScreen extends StatefulWidget {
  const GoldChitTrackerScreen({super.key});

  @override
  State<GoldChitTrackerScreen> createState() => _GoldChitTrackerScreenState();
}

class _GoldChitTrackerScreenState extends State<GoldChitTrackerScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String? _uid;
  
  List<Map<String, dynamic>> _plans = [];
  Map<String, dynamic>? _selectedPlan;
  bool _isLoadingPlans = true;
  String? _defaultPlanId;
  StreamSubscription? _ownedPlansSubscription;
  StreamSubscription? _sharedPlansSubscription;
  StreamSubscription? _userSubscription;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    if (_uid != null) {
      _listenToUserPreferences();
    }
  }

  @override
  void dispose() {
    _ownedPlansSubscription?.cancel();
    _sharedPlansSubscription?.cancel();
    _userSubscription?.cancel();
    super.dispose();
  }

  void _listenToUserPreferences() {
    if (_uid == null) return;

    // Listen to user document for default plan ID preference
    _userSubscription = _db.collection('users').doc(_uid).snapshots().listen((doc) {
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        _defaultPlanId = data['defaultGoldChitPlanId'] as String?;
      }
      _loadPlans();
    });
  }

  Future<void> _loadPlans() async {
    if (_uid == null) return;
    
    _ownedPlansSubscription?.cancel();
    _sharedPlansSubscription?.cancel();

    List<Map<String, dynamic>> ownedPlans = [];
    List<Map<String, dynamic>> sharedPlans = [];

    void updatePlansState() {
      if (!mounted) return;

      // Merge and deduplicate by document id
      final Map<String, Map<String, dynamic>> merged = {};
      for (final p in ownedPlans) {
        if (p['id'] != null) merged[p['id']] = p;
      }
      for (final p in sharedPlans) {
        if (p['id'] != null) merged[p['id']] = p;
      }

      final plansList = merged.values.toList();

      // Sort in memory by createdAt descending
      plansList.sort((a, b) {
        final aTime = a['createdAt'] as Timestamp?;
        final bTime = b['createdAt'] as Timestamp?;
        if (aTime == null || bTime == null) return 0;
        return bTime.compareTo(aTime);
      });

      setState(() {
        _plans = plansList;
        _isLoadingPlans = false;
        
        // Auto-select plan: Default plan takes priority, otherwise the first plan
        if (_plans.isNotEmpty) {
          final defaultPlanIndex = _plans.indexWhere((p) => p['id'] == _defaultPlanId);
          if (defaultPlanIndex != -1) {
            _selectedPlan = _plans[defaultPlanIndex];
          } else {
            // Keep current selected plan if it still exists in the list
            final stillExists = _selectedPlan != null && _plans.any((p) => p['id'] == _selectedPlan!['id']);
            if (!stillExists) {
              _selectedPlan = _plans.first;
            }
          }
        } else {
          _selectedPlan = null;
        }
      });
    }

    _ownedPlansSubscription = _db.collection('gold_chits')
       .where('ownerId', isEqualTo: _uid)
       .snapshots()
       .listen((snapshot) {
         ownedPlans = snapshot.docs.map((doc) {
           final data = doc.data();
           data['id'] = doc.id;
           return data;
         }).toList();
         updatePlansState();
       }, onError: (err) {
         print("Error loading owned plans: $err");
         updatePlansState();
       });

    _sharedPlansSubscription = _db.collection('gold_chits')
       .where('sharedWith', arrayContains: _uid)
       .snapshots()
       .listen((snapshot) {
         sharedPlans = snapshot.docs.map((doc) {
           final data = doc.data();
           data['id'] = doc.id;
           return data;
         }).toList();
         updatePlansState();
       }, onError: (err) {
         print("Error loading shared plans: $err");
         updatePlansState();
       });
  }

  Future<void> _setDefaultPlan(Map<String, dynamic> plan) async {
    if (_uid == null) return;

    await _db.collection('users').doc(_uid).update({
      'defaultGoldChitPlanId': plan['id'],
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${plan['name']}" set as default plan.')),
      );
    }
  }

  void _showAddPlanDialog() {
    final nameController = TextEditingController();
    final installmentController = TextEditingController();
    
    int startMonth = DateTime.now().month;
    int startYear = DateTime.now().year;
    int endMonth = DateTime.now().add(const Duration(days: 330)).month; // approx 11 months
    int endYear = DateTime.now().add(const Duration(days: 330)).year;

    final monthsList = List.generate(12, (index) => index + 1);
    final yearsList = List.generate(10, (index) => DateTime.now().year - 2 + index);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.add_chart, color: Colors.deepPurple),
                  SizedBox(width: 8),
                  Text('Create Gold Chit Plan'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Plan Name',
                        hintText: 'e.g., Family Chit 2026',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: installmentController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Monthly Installment (₹)',
                        hintText: 'e.g., 5000',
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Start Month & Year', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButton<int>(
                            value: startMonth,
                            isExpanded: true,
                            items: monthsList.map((m) {
                              return DropdownMenuItem(
                                value: m,
                                child: Text(DateFormat('MMMM').format(DateTime(2026, m))),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setDialogState(() => startMonth = val);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButton<int>(
                            value: startYear,
                            isExpanded: true,
                            items: yearsList.map((y) {
                              return DropdownMenuItem(
                                value: y,
                                child: Text('$y'),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setDialogState(() => startYear = val);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('End Month & Year', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButton<int>(
                            value: endMonth,
                            isExpanded: true,
                            items: monthsList.map((m) {
                              return DropdownMenuItem(
                                value: m,
                                child: Text(DateFormat('MMMM').format(DateTime(2026, m))),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setDialogState(() => endMonth = val);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButton<int>(
                            value: endYear,
                            isExpanded: true,
                            items: yearsList.map((y) {
                              return DropdownMenuItem(
                                value: y,
                                child: Text('$y'),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setDialogState(() => endYear = val);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    final installment = double.tryParse(installmentController.text.trim());
                    if (name.isEmpty || installment == null || installment <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a valid plan name and installment amount.')),
                      );
                      return;
                    }

                    // Calculate total months
                    final startDateTime = DateTime(startYear, startMonth);
                    final endDateTime = DateTime(endYear, endMonth);
                    if (endDateTime.isBefore(startDateTime)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('End date cannot be before start date.')),
                      );
                      return;
                    }

                    // Count total months (inclusive)
                    final totalMonths = ((endDateTime.year - startDateTime.year) * 12) + (endDateTime.month - startDateTime.month) + 1;

                    Navigator.pop(context);
                    await _createNewPlan(name, installment, startMonth, startYear, endMonth, endYear, totalMonths);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _createNewPlan(
    String name, 
    double installment, 
    int startMonth, 
    int startYear, 
    int endMonth, 
    int endYear, 
    int totalMonths
  ) async {
    if (_uid == null) return;

    // Save plans to top-level gold_chits collection so it can be shared
    final planRef = _db.collection('gold_chits').doc();

    final planData = {
      'name': name,
      'monthlyInstallment': installment,
      'startMonth': '$startYear-${startMonth.toString().padLeft(2, '0')}',
      'endMonth': '$endYear-${endMonth.toString().padLeft(2, '0')}',
      'totalMonths': totalMonths,
      'createdAt': FieldValue.serverTimestamp(),
      'ownerId': _uid,
      'sharedWith': <String>[],
      'status': 'active',
    };

    await planRef.set(planData);

    // If it's the user's first plan, set as their default
    if (_defaultPlanId == null) {
      await _db.collection('users').doc(_uid).update({
        'defaultGoldChitPlanId': planRef.id,
      });
    }

    // Populate installments subcollection
    final batch = _db.batch();
    for (int i = 0; i < totalMonths; i++) {
      final currentMonthDate = DateTime(startYear, startMonth + i);
      final monthKey = DateFormat('yyyy-MM').format(currentMonthDate);
      
      final installmentDocRef = planRef.collection('installments').doc(monthKey);
      batch.set(installmentDocRef, {
        'monthKey': monthKey,
        'status': 'unpaid',
      });
    }

    await batch.commit();
  }

  void _showManageUsersDialog() {
    if (_selectedPlan == null || _uid == null) return;

    final List<dynamic> currentSharedWith = _selectedPlan!['sharedWith'] ?? [];
    final List<String> selectedUids = List<String>.from(currentSharedWith);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.group_add, color: Colors.deepPurple),
                  SizedBox(width: 8),
                  Text('Share Plan with Users'),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 300,
                child: StreamBuilder<QuerySnapshot>(
                  stream: _db.collection('usernames').snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(child: Text('No users found.'));
                    }

                    final docs = snapshot.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final userId = data['uid'] ?? '';
                      return userId.isNotEmpty && userId != _uid;
                    }).toList();

                    if (docs.isEmpty) {
                      return const Center(child: Text('No other users available.'));
                    }

                    return ListView.builder(
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final username = docs[index].id;
                        final data = docs[index].data() as Map<String, dynamic>;
                        final userId = data['uid'] as String;

                        final isChecked = selectedUids.contains(userId);

                        return CheckboxListTile(
                          title: Text(username, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(data['email'] ?? 'No email'),
                          value: isChecked,
                          activeColor: Colors.deepPurple,
                          onChanged: (val) {
                            setDialogState(() {
                              if (val == true) {
                                selectedUids.add(userId);
                              } else {
                                selectedUids.remove(userId);
                              }
                            });
                          },
                        );
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _updateSharedUsers(selectedUids);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _updateSharedUsers(List<String> uids) async {
    if (_selectedPlan == null || _uid == null) return;

    final planRef = _db.collection('gold_chits').doc(_selectedPlan!['id']);
    await planRef.update({
      'sharedWith': uids,
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan sharing updated successfully.')),
      );
    }
  }

  // Time-Sensitive Historical Gold Rate Lookup Logic
  Future<double?> _fetchHistoricalPrice(DateTime selectedDateTime) async {
    try {
      final DateFormat dateFormat = DateFormat('yyyy-MM-dd');
      final String dateStr = dateFormat.format(selectedDateTime);
      final prevDateStr = dateFormat.format(selectedDateTime.subtract(const Duration(days: 1)));

      final querySnapshot = await _db.collection('global_gold_prices')
          .where('date', whereIn: [prevDateStr, dateStr])
          .get();

      if (querySnapshot.docs.isEmpty) {
        return null;
      }

      final List<GoldPrice> prices = querySnapshot.docs
          .map((doc) => GoldPrice.fromJson(doc.data(), doc.id))
          .toList();

      // Sort by timestamp ascending
      prices.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // Define time limits for the selected day
      final morningLimit = DateTime(selectedDateTime.year, selectedDateTime.month, selectedDateTime.day, 11, 0);
      final eveningLimit = DateTime(selectedDateTime.year, selectedDateTime.month, selectedDateTime.day, 19, 0);

      if (selectedDateTime.isBefore(morningLimit)) {
        // Fetch latest price before 11:00 AM on selected date (typically previous day's latest price)
        GoldPrice? bestPrice;
        for (var p in prices) {
          final pTime = DateTime.tryParse(p.timestamp);
          if (pTime != null && pTime.isBefore(morningLimit)) {
            bestPrice = p;
          }
        }
        return bestPrice?.price;
      } else if (selectedDateTime.isAfter(eveningLimit)) {
        // Fetch July 10, 7:00 PM (Evening) price or fall back to morning price
        GoldPrice? morningPrice;
        GoldPrice? eveningPrice;
        for (var p in prices) {
          final pTime = DateTime.tryParse(p.timestamp);
          if (pTime != null && pTime.year == selectedDateTime.year && pTime.month == selectedDateTime.month && pTime.day == selectedDateTime.day) {
            if (pTime.hour >= 19) {
              eveningPrice = p;
            } else if (pTime.hour >= 11) {
              morningPrice = p;
            }
          }
        }
        return eveningPrice?.price ?? morningPrice?.price;
      } else {
        // Between 11:00 AM & 7:00 PM: Fetch 11:00 AM morning price
        GoldPrice? morningPrice;
        for (var p in prices) {
          final pTime = DateTime.tryParse(p.timestamp);
          if (pTime != null && pTime.year == selectedDateTime.year && pTime.month == selectedDateTime.month && pTime.day == selectedDateTime.day) {
            if (pTime.hour >= 11 && pTime.hour < 19) {
              morningPrice = p;
            }
          }
        }
        if (morningPrice == null) {
          // Fallback to any price on that day
          for (var p in prices) {
            final pTime = DateTime.tryParse(p.timestamp);
            if (pTime != null && pTime.year == selectedDateTime.year && pTime.month == selectedDateTime.month && pTime.day == selectedDateTime.day) {
              morningPrice = p;
              break;
            }
          }
        }
        return morningPrice?.price;
      }
    } catch (e) {
      debugPrint('Error looking up historical gold price: $e');
    }
    return null;
  }

  void _showLogPaymentDialog(Map<String, dynamic> installment) {
    if (_selectedPlan == null || _uid == null) return;

    final String monthKey = installment['monthKey'] ?? '';
    final String initialStatus = installment['status'] ?? 'unpaid';
    
    DateTime selectedDateTime = DateTime.now();
    if (installment['paymentDate'] != null) {
      selectedDateTime = DateTime.parse(installment['paymentDate']);
    } else {
      // Set to the first day of the corresponding monthKey at 12:00 PM as default
      final parts = monthKey.split('-');
      if (parts.length == 2) {
        final year = int.tryParse(parts[0]) ?? DateTime.now().year;
        final month = int.tryParse(parts[1]) ?? DateTime.now().month;
        selectedDateTime = DateTime(year, month, 1, 12, 0);
      }
    }

    final rateController = TextEditingController(
      text: installment['goldRatePerGram'] != null ? installment['goldRatePerGram'].toString() : '',
    );
    
    bool isFetchingRate = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> fetchRate() async {
              setDialogState(() => isFetchingRate = true);
              final rate = await _fetchHistoricalPrice(selectedDateTime);
              setDialogState(() {
                isFetchingRate = false;
                if (rate != null) {
                  rateController.text = rate.toStringAsFixed(2);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No historical price found in database for selected time. Please enter manually.')),
                  );
                }
              });
            }

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.payment, color: Colors.deepPurple),
                  const SizedBox(width: 8),
                  Text('Log Payment - ${DateFormat('MMMM yyyy').format(DateTime.parse('$monthKey-01'))}'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Payment Date & Time', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: selectedDateTime,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (date != null && context.mounted) {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(selectedDateTime),
                          );
                          if (time != null) {
                            setDialogState(() {
                              selectedDateTime = DateTime(
                                date.year,
                                date.month,
                                date.day,
                                time.hour,
                                time.minute,
                              );
                            });
                            // Auto-fetch price for the selected date/time
                            fetchRate();
                          }
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(DateFormat('dd MMM yyyy, hh:mm a').format(selectedDateTime)),
                            const Icon(Icons.calendar_today, size: 18, color: Colors.deepPurple),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: rateController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: '22K Gold Price (₹/Gram)',
                              hintText: 'e.g., 7250',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        isFetchingRate 
                          ? const SizedBox(width: 40, height: 40, child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator(strokeWidth: 2)))
                          : TextButton.icon(
                              onPressed: fetchRate,
                              icon: const Icon(Icons.download, size: 18),
                              label: const Text('Fetch'),
                              style: TextButton.styleFrom(foregroundColor: Colors.deepPurple),
                            ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                if (initialStatus == 'paid')
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _deletePayment(monthKey);
                    },
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Remove Payment'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final rate = double.tryParse(rateController.text.trim());
                    if (rate == null || rate <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a valid gold price.')),
                      );
                      return;
                    }

                    final double monthlyInstallment = _selectedPlan!['monthlyInstallment'];
                    final double gramsAccumulated = monthlyInstallment / rate;

                    Navigator.pop(context);
                    await _savePayment(monthKey, selectedDateTime, rate, gramsAccumulated);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _savePayment(String monthKey, DateTime date, double rate, double grams) async {
    if (_selectedPlan == null || _uid == null) return;
    
    final ref = _db.collection('gold_chits')
                   .doc(_selectedPlan!['id'])
                   .collection('installments')
                   .doc(monthKey);

    await ref.update({
      'status': 'paid',
      'paymentDate': date.toIso8601String(),
      'goldRatePerGram': rate,
      'gramsAccumulated': grams,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _uid,
    });
  }

  Future<void> _deletePayment(String monthKey) async {
    if (_selectedPlan == null || _uid == null) return;

    final ref = _db.collection('gold_chits')
                   .doc(_selectedPlan!['id'])
                   .collection('installments')
                   .doc(monthKey);

    await ref.update({
      'status': 'unpaid',
      'paymentDate': FieldValue.delete(),
      'goldRatePerGram': FieldValue.delete(),
      'gramsAccumulated': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _uid,
    });
  }

  String _formatMonthHeader(String startMonthStr, String endMonthStr) {
    try {
      final start = DateTime.parse('$startMonthStr-01');
      final end = DateTime.parse('$endMonthStr-01');
      return 'From ${DateFormat('MMMM yyyy').format(start)} to ${DateFormat('MMMM yyyy').format(end)}';
    } catch (_) {}
    return 'From $startMonthStr to $endMonthStr';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gold Chit Tracker'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add New Plan',
            onPressed: _showAddPlanDialog,
          ),
        ],
      ),
      body: _isLoadingPlans 
        ? const Center(child: CircularProgressIndicator())
        : _plans.isEmpty 
          ? _buildEmptyState()
          : _buildDashboard(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.savings_outlined, size: 80, color: Colors.deepPurple),
            const SizedBox(height: 16),
            const Text(
              'No Gold Chit Schemes Found',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Create a monthly gold chit scheme to track your payments, purchase rates, and accumulated gold weight.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showAddPlanDialog,
              icon: const Icon(Icons.add),
              label: const Text('Create First Plan'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboard() {
    if (_selectedPlan == null) return const SizedBox();

    final isOwner = _selectedPlan!['ownerId'] == _uid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Selector Row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          child: Row(
            children: [
              const Icon(Icons.assignment, color: Colors.deepPurple),
              const SizedBox(width: 8),
              Expanded(
                child: PopupMenuButton<Map<String, dynamic>>(
                  initialValue: _selectedPlan,
                  onSelected: (plan) {
                    setState(() {
                      _selectedPlan = plan;
                    });
                  },
                  itemBuilder: (context) {
                    return _plans.map((p) {
                      final planId = p['id'] as String;
                      final isPlanDefault = planId == _defaultPlanId;

                      return PopupMenuItem<Map<String, dynamic>>(
                        value: p,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                p['name'] ?? '',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: p['id'] == _selectedPlan?['id'] ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                            if (isPlanDefault)
                              const Icon(Icons.star, color: Colors.amber, size: 16),
                          ],
                        ),
                      );
                    }).toList();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.deepPurple.shade200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _selectedPlan?['name'] ?? '',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, color: Colors.deepPurple),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.star_border, color: Colors.amber),
                tooltip: 'Set as Default',
                onPressed: () => _setDefaultPlan(_selectedPlan!),
              ),
              // Add users button only for Owner
              if (isOwner)
                IconButton(
                  icon: const Icon(Icons.group_add, color: Colors.deepPurple),
                  tooltip: 'Share Plan',
                  onPressed: _showManageUsersDialog,
                ),
            ],
          ),
        ),

        // Live stats summary stream
        StreamBuilder<QuerySnapshot>(
          stream: _db.collection('gold_chits')
                     .doc(_selectedPlan!['id'])
                     .collection('installments')
                     .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox();
            
            final installments = snapshot.data!.docs;
            final paidInstallments = installments.where((doc) => doc['status'] == 'paid').toList();

            final double monthlyInstallment = _selectedPlan!['monthlyInstallment'] ?? 0.0;
            final int totalMonths = _selectedPlan!['totalMonths'] ?? 0;
            
            final double totalPaid = paidInstallments.length * monthlyInstallment;
            double totalGrams = 0.0;
            for (var doc in paidInstallments) {
              totalGrams += (doc['gramsAccumulated'] ?? 0.0) as double;
            }

            final remainingMonths = totalMonths - paidInstallments.length;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                color: Colors.deepPurple.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text(
                        _formatMonthHeader(_selectedPlan!['startMonth'], _selectedPlan!['endMonth']),
                        style: TextStyle(fontWeight: FontWeight.w600, color: Colors.deepPurple.shade900),
                      ),
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildSummaryItem('Total Paid', '₹${NumberFormat('#,##,###').format(totalPaid)}', Icons.payment),
                          _buildSummaryItem('Total Grams', '${totalGrams.toStringAsFixed(4)} g', Icons.scale),
                          _buildSummaryItem('Remaining', '$remainingMonths / $totalMonths m', Icons.timelapse),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 12),

        // Installment Details Table Title
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.0),
          child: Text(
            'Installments History',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),

        // Installment detailed list
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _db.collection('gold_chits')
                       .doc(_selectedPlan!['id'])
                       .collection('installments')
                       .orderBy('monthKey', descending: false)
                       .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Text('No installment periods generated.'));
              }

              final docs = snapshot.data!.docs;

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  data['monthKey'] = docs[index].id;
                  final isPaid = data['status'] == 'paid';
                  final monthDate = DateTime.parse('${data['monthKey']}-01');

                  return Card(
                    elevation: 1,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    child: ListTile(
                      onTap: () => _showLogPaymentDialog(data),
                      leading: CircleAvatar(
                        backgroundColor: isPaid ? Colors.green.shade50 : Colors.grey.shade100,
                        foregroundColor: isPaid ? Colors.green : Colors.grey,
                        child: Text('${index + 1}'),
                      ),
                      title: Text(
                        DateFormat('MMMM yyyy').format(monthDate),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: isPaid 
                        ? Text(
                            'Paid on: ${DateFormat('dd MMM yy, hh:mm a').format(DateTime.parse(data['paymentDate']))}',
                            style: const TextStyle(fontSize: 12),
                          )
                        : Text('Not paid yet', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (isPaid) ...[
                            Text(
                              '${(data['gramsAccumulated'] as double).toStringAsFixed(4)} g',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple),
                            ),
                            Text(
                              '@ ₹${data['goldRatePerGram']}/g',
                              style: const TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                          ] else ...[
                            Icon(Icons.add_circle_outline, color: Colors.grey.shade400),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.deepPurple.shade700, size: 24),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
      ],
    );
  }
}
