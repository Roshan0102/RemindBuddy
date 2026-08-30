import 'dart:async';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/gold_price_service.dart';
import '../models/gold_price.dart';
import 'gold_chit_tracker_screen.dart';

class GoldScreen extends StatefulWidget {
  const GoldScreen({super.key});

  @override
  State<GoldScreen> createState() => _GoldScreenState();
}

class _GoldScreenState extends State<GoldScreen> {
  final GoldPriceService _goldService = GoldPriceService();
  bool _isGeneratingAI = false;
  bool _isGeneratingChit = false;
  int _aiActiveTab = 1; // 1 for Chit Assistant, 0 for Forecast
  String _selectedChartRange = 'This Month';
  
  String? _uid;
  bool _askGeminiEnabled = false;
  bool _goldChitEnabled = false;
  StreamSubscription? _userSubscription;
  late Stream<List<GoldPrice>> _goldPricesStream;
  Set<String> _paidChitDateKeys = {};
  List<QueryDocumentSnapshot> _ownedChitDocs = [];
  List<QueryDocumentSnapshot> _sharedChitDocs = [];
  StreamSubscription? _ownedChitsSub;
  StreamSubscription? _sharedChitsSub;

  @override
  void initState() {
    super.initState();
    _goldPricesStream = _goldService.getGlobalGoldPricesStream();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    if (_uid != null) {
      _userSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .snapshots()
          .listen((doc) {
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          final enabledModules = List<String>.from(data['enabledModules'] ?? ['gold']);
          if (mounted) {
            setState(() {
              _askGeminiEnabled = enabledModules.contains('ask_gemini');
              _goldChitEnabled = enabledModules.contains('gold_chit');
            });
          }
        }
      });
      _initChitPaymentsListener();
    }
  }

  void _initChitPaymentsListener() {
    if (_uid == null) return;

    void updateAllPaidDates() async {
      final allDocs = [..._ownedChitDocs, ..._sharedChitDocs];
      final uniqueDocs = {for (var d in allDocs) d.id: d}.values;

      Set<String> dateKeys = {};
      for (var doc in uniqueDocs) {
        try {
          final instSnap = await doc.reference
              .collection('installments')
              .where('status', isEqualTo: 'paid')
              .get();
          for (var instDoc in instSnap.docs) {
            final pDateStr = instDoc.data()['paymentDate'] as String?;
            if (pDateStr != null) {
              final pDate = DateTime.tryParse(pDateStr);
              if (pDate != null) {
                final dateKey = DateFormat('yyyy-MM-dd').format(pDate.toLocal());
                dateKeys.add(dateKey);
              }
            }
          }
        } catch (e) {
          debugPrint('Error fetching installments for chit: $e');
        }
      }
      if (mounted) {
        setState(() {
          _paidChitDateKeys = dateKeys;
        });
      }
    }

    _ownedChitsSub = FirebaseFirestore.instance
        .collection('gold_chits')
        .where('ownerId', isEqualTo: _uid)
        .snapshots()
        .listen((snap) {
      _ownedChitDocs = snap.docs;
      updateAllPaidDates();
    });

    _sharedChitsSub = FirebaseFirestore.instance
        .collection('gold_chits')
        .where('sharedWith', arrayContains: _uid)
        .snapshots()
        .listen((snap) {
      _sharedChitDocs = snap.docs;
      updateAllPaidDates();
    });
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    _ownedChitsSub?.cancel();
    _sharedChitsSub?.cancel();
    super.dispose();
  }


  void _showSourceChecker() async {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setInternalState) {
            return AlertDialog(
              title: const Text('Live Source Checker'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Fetching current prices from all scrapers directly (No DB write)...'),
                  const SizedBox(height: 20),
                  FutureBuilder<Map<String, dynamic>>(
                    future: _goldService.checkAllSourcesManual(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const CircularProgressIndicator();
                      }
                      final data = snapshot.data ?? {};
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sourceRow('LiveChennai', data['live_chennai']),
                          _sourceRow('BankBazaar', data['bank_bazaar']),
                          const Divider(),
                          Text('As of: ${data['timestamp'] ?? 'Now'}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      );
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  Widget _sourceRow(String name, dynamic result) {
    bool isSuccess = result is num;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(
            isSuccess ? '₹ $result' : '❌ $result',
            style: TextStyle(
              color: isSuccess ? Colors.green[700] : Colors.red,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace'
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GoldPrice>>(
      stream: _goldPricesStream,
      builder: (context, snapshot) {
        final history = snapshot.data ?? [];
        final currentPrice = history.isNotEmpty ? history.first : null;
        final priceDiff = currentPrice != null ? currentPrice.priceChange : 0.0;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Gold Rates (22K)'),
            actions: [
              if (_goldChitEnabled)
                IconButton(
                  icon: const Icon(Icons.savings_outlined),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const GoldChitTrackerScreen()),
                  ),
                  tooltip: 'Gold Chit Tracker',
                ),
              IconButton(
                icon: const Icon(Icons.compare_arrows),
                onPressed: _showSourceChecker,
                tooltip: 'Check Sources',
              ),
            ],
          ),
          body: snapshot.connectionState == ConnectionState.waiting && history.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : history.isEmpty
                  ? const Center(child: Text('No gold data in Cloud yet'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildCurrentPriceCard(currentPrice, priceDiff),
                          const SizedBox(height: 24),
                          _buildAIInsightsSection(),
                          const SizedBox(height: 24),
                          const Text(
                            'Recent History',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          _buildHistoryTable(history.take(10).toList()),
                          const SizedBox(height: 24),
                          const Text(
                            'Price Trend',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
                          _buildChartFilterButtons(),
                          const SizedBox(height: 16),
                          _buildModernChart(history),
                          const SizedBox(height: 16),
                          _buildScheduleInfo(),
                        ],
                      ),
                    ),
        );
      },
    );
  }

  Widget _buildCurrentPriceCard(GoldPrice? currentPrice, double diff) {
    if (currentPrice == null) return const SizedBox.shrink();
    
    final price = currentPrice.price;
    
    Color diffColor = Colors.grey;
    IconData diffIcon = Icons.remove;
    String diffText = "";
    
    if (diff > 0) {
      diffColor = Colors.greenAccent.shade400;
      diffIcon = Icons.trending_up;
      diffText = "+₹${diff.toStringAsFixed(0)}";
    } else if (diff < 0) {
      diffColor = Colors.redAccent.shade200;
      diffIcon = Icons.trending_down;
      diffText = "-₹${diff.abs().toStringAsFixed(0)}";
    }
    
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFBF953F), // Dark Gold
            Color(0xFFFCF6BA), // Light Gold
            Color(0xFFB38728), // Golden Brown
            Color(0xFFFBF5B7), // Pale Gold
            Color(0xFFAA771C), // Deep Gold
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB38728).withValues(alpha: 0.4),
            blurRadius: 15,
            spreadRadius: 2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(28.0),
        child: Column(
          children: [
            Text(
              'LATEST GOLD RATE (22K)', 
              style: TextStyle(
                fontSize: 13, 
                color: Colors.black.withValues(alpha: 0.6),
                fontWeight: FontWeight.bold,
                letterSpacing: 2.0,
              )
            ),
            const SizedBox(height: 16),
            Text(
              '₹ ${price.toStringAsFixed(0)}', 
              style: const TextStyle(
                fontSize: 58, 
                fontWeight: FontWeight.w900, 
                color: Colors.black87,
                letterSpacing: -1.0,
              ),
            ),
            const SizedBox(height: 16),
             if (diff != 0) 
               Container(
                 padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                 decoration: BoxDecoration(
                   color: Colors.black.withValues(alpha: 0.1),
                   borderRadius: BorderRadius.circular(30),
                 ),
                 child: Row(
                   mainAxisSize: MainAxisSize.min,
                   mainAxisAlignment: MainAxisAlignment.center,
                   children: [
                     Icon(diffIcon, color: diffColor, size: 24),
                     const SizedBox(width: 8),
                     Text(
                       diffText,
                       style: TextStyle(
                         color: diffColor, 
                         fontWeight: FontWeight.w800, 
                         fontSize: 20
                       ),
                     ),
                   ],
                 ),
               ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Updated: ${_formatDate(currentPrice.timestamp)} via ${currentPrice.source}', 
                style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryTable(List<GoldPrice> history) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(2.2),
            1: FlexColumnWidth(2.0),
            2: FlexColumnWidth(2.0),
            3: FlexColumnWidth(1.8),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
              ),
              children: const [
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.0),
                  child: Text('Date & Time', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.0),
                  child: Text('Price (22K)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.0),
                  child: Text('Change', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.0),
                  child: Text('Source', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),
                ),
              ],
            ),
            ...history.map((price) {
              final change = price.priceChange;
              return TableRow(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.1))),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: Text(_formatDate(price.timestamp), style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: Text('₹ ${price.price.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: change != 0
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                change > 0 ? Icons.arrow_upward : Icons.arrow_downward,
                                size: 14,
                                color: change > 0 ? Colors.green : Colors.red,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '₹${change.abs().toStringAsFixed(0)}',
                                style: TextStyle(
                                  color: change > 0 ? Colors.green : Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          )
                        : const Text('₹0', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: Text(price.source, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildChartFilterButtons() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: ['7D', 'This Month', '1M', '3M', '6M', '1Y', 'Max'].map((range) {
          final isSelected = _selectedChartRange == range;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => setState(() => _selectedChartRange = range),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? const LinearGradient(
                          colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                        )
                      : null,
                  color: isSelected
                      ? null
                      : (isDark ? const Color(0xFF1E293B) : Colors.white),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFFF59E0B)
                        : (isDark ? Colors.white12 : Colors.grey.shade300),
                    width: isSelected ? 1.5 : 1.0,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  range,
                  style: GoogleFonts.outfit(
                    color: isSelected
                        ? Colors.black87
                        : (isDark ? Colors.white70 : Colors.blueGrey.shade800),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildModernChart(List<GoldPrice> history) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    if (history.length < 2) return const SizedBox.shrink();

    // Filter history based on range
    DateTime now = DateTime.now();
    List<GoldPrice> filteredHistory;
    
    if (_selectedChartRange == 'Max') {
      filteredHistory = history;
    } else if (_selectedChartRange == 'This Month') {
      final startOfMonth = DateTime(now.year, now.month, 1);
      filteredHistory = history.where((p) {
        try {
          return DateTime.parse(p.timestamp).isAfter(startOfMonth);
        } catch (_) {
          return false;
        }
      }).toList();
    } else {
      Duration duration;
      switch (_selectedChartRange) {
        case '7D':
          duration = const Duration(days: 7);
          break;
        case '1M':
          duration = const Duration(days: 30);
          break;
        case '3M':
          duration = const Duration(days: 90);
          break;
        case '6M':
          duration = const Duration(days: 180);
          break;
        case '1Y':
          duration = const Duration(days: 365);
          break;
        default:
          duration = const Duration(days: 7);
      }
      
      final cutoff = now.subtract(duration);
      filteredHistory = history.where((p) {
        try {
          return DateTime.parse(p.timestamp).isAfter(cutoff);
        } catch (_) {
          return false;
        }
      }).toList();
    }

    if (filteredHistory.length < 2) {
      return Container(
        padding: const EdgeInsets.all(32.0),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131C2E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
        ),
        child: Center(
          child: Text(
            'Not enough data for this range',
            style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade600),
          ),
        ),
      );
    }

    // Chart needs chronological order
    final sortedHistory = List<GoldPrice>.from(filteredHistory).reversed.toList();

    // Identify data points that coincide with a Gold Chit installment payment date
    final paidPoints = sortedHistory.where((p) {
      try {
        final dt = DateTime.parse(p.timestamp).toLocal();
        final key = DateFormat('yyyy-MM-dd').format(dt);
        return _paidChitDateKeys.contains(key);
      } catch (_) {
        return false;
      }
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131C2E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFFF59E0B).withValues(alpha: 0.25) : Colors.amber.shade100,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withValues(alpha: 0.35) : Colors.amber.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            SizedBox(
              height: 250,
              child: SfCartesianChart(
                plotAreaBorderWidth: 0,
                primaryXAxis: CategoryAxis(
                  majorGridLines: const MajorGridLines(width: 0),
                  axisLine: AxisLine(color: isDark ? Colors.white24 : Colors.grey.shade300),
                  labelStyle: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.blueGrey.shade700,
                  ),
                  labelIntersectAction: AxisLabelIntersectAction.hide,
                  labelRotation: 0,
                ),
                primaryYAxis: NumericAxis(
                  numberFormat: NumberFormat.currency(symbol: '₹', decimalDigits: 0),
                  axisLine: const AxisLine(width: 0),
                  majorGridLines: MajorGridLines(
                    color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                    dashArray: const <double>[4, 4],
                  ),
                  labelStyle: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.blueGrey.shade700,
                  ),
                ),
                tooltipBehavior: TooltipBehavior(
                  enable: true,
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
                  textStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  format: 'point.x : point.y',
                ),
                series: <CartesianSeries>[
                  SplineAreaSeries<GoldPrice, String>(
                    name: 'Gold Rate (22K)',
                    dataSource: sortedHistory,
                    xValueMapper: (GoldPrice p, _) => _formatChartDate(p.timestamp),
                    yValueMapper: (GoldPrice p, _) => p.price,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.40 : 0.25),
                        const Color(0xFFF59E0B).withValues(alpha: 0.0),
                      ],
                    ),
                    borderColor: isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
                    borderWidth: 2.8,
                    markerSettings: MarkerSettings(
                      isVisible: sortedHistory.length <= 25,
                      shape: DataMarkerType.circle,
                      width: 5,
                      height: 5,
                      color: const Color(0xFFFBBF24),
                      borderColor: isDark ? const Color(0xFF78350F) : Colors.white,
                      borderWidth: 1.5,
                    ),
                  ),
                  if (paidPoints.isNotEmpty)
                    ScatterSeries<GoldPrice, String>(
                      name: 'Gold Chit Paid',
                      dataSource: paidPoints,
                      xValueMapper: (GoldPrice p, _) => _formatChartDate(p.timestamp),
                      yValueMapper: (GoldPrice p, _) => p.price,
                      markerSettings: const MarkerSettings(
                        isVisible: true,
                        shape: DataMarkerType.diamond,
                        width: 14,
                        height: 14,
                        color: Color(0xFFFDE047),
                        borderColor: Color(0xFFEA580C),
                        borderWidth: 2.5,
                      ),
                    ),
                ],
              ),
            ),
            if (_paidChitDateKeys.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.3 : 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFDE047),
                        shape: BoxShape.rectangle,
                        border: Border.all(color: const Color(0xFFEA580C), width: 2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Glowing Diamond = Gold Chit Installment Paid Date',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isDark ? const Color(0xFFFBBF24) : Colors.orange.shade900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleInfo() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131C2E) : const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.blueAccent.withValues(alpha: 0.2) : Colors.blue.shade100,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule_rounded, color: Colors.blueAccent, size: 20),
              const SizedBox(width: 8),
              Text('Notification Schedule (IST)', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 12),
          _scheduleRow('11:00 AM', 'Daily rate update (Always)', isDark),
          _scheduleRow('07:00 PM', 'Evening check (Only if price differs)', isDark),
        ],
      ),
    );
  }

  Widget _scheduleRow(String time, String desc, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        children: [
          Text(time, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent, fontSize: 12)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              desc,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.blueGrey.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatChartDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      if (_selectedChartRange == '7D' || _selectedChartRange == 'This Month' || _selectedChartRange == '1M') {
        return DateFormat('d MMM').format(dt);
      } else if (_selectedChartRange == '3M' || _selectedChartRange == '6M') {
        return DateFormat('d MMM').format(dt);
      } else {
        return DateFormat('MMM yy').format(dt);
      }
    } catch (e) {
      return dateStr;
    }
  }

  String _formatDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      return DateFormat('dd/MM HH:mm').format(dt);
    } catch (e) {
      return dateStr;
    }
  }

  Widget _buildAIInsightsSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade900, Colors.indigo.shade800],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.psychology, color: Colors.cyanAccent),
                SizedBox(width: 8),
                Text(
                  'Gemini AI Assistant',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _aiActiveTab = 0),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _aiActiveTab == 0 ? Colors.indigo.shade800 : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                      ),
                      child: Text(
                        'Market Forecast',
                        style: TextStyle(
                          fontWeight: _aiActiveTab == 0 ? FontWeight.bold : FontWeight.normal,
                          color: _aiActiveTab == 0 ? Colors.indigo.shade800 : Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _aiActiveTab = 1),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _aiActiveTab == 1 ? Colors.indigo.shade800 : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                      ),
                      child: Text(
                        'Gold Chit Assistant',
                        style: TextStyle(
                          fontWeight: _aiActiveTab == 1 ? FontWeight.bold : FontWeight.normal,
                          color: _aiActiveTab == 1 ? Colors.indigo.shade800 : Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _aiActiveTab == 0 ? _buildMarketForecastContent() : _buildGoldChitAdviceContent(),
        ],
      ),
    );
  }

  String _formatAITimestamp(String? tsStr) {
    if (tsStr == null || tsStr.isEmpty) return 'N/A';
    try {
      final dt = DateTime.parse(tsStr).toLocal();
      return DateFormat('MMMM d, yyyy h:mm a').format(dt);
    } catch (e) {
      return tsStr;
    }
  }

  Widget _buildMarketForecastContent() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('gold_ai_insights').doc('latest').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final data = snapshot.data?.data() as Map<String, dynamic>?;

        if (data == null) {
          return Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                const Icon(Icons.psychology_outlined, size: 48, color: Colors.amber),
                const SizedBox(height: 12),
                const Text(
                  'No AI predictions generated yet',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Get Gemini AI to analyze recent prices and gold market news to predict the future rate.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 16),
                _buildGenerateAIButton(),
              ],
            ),
          );
        }

        final sentiment = data['sentiment'] ?? 'neutral';
        final sentimentScore = data['sentimentScore'] ?? 0;
        final sentimentSummary = data['sentimentSummary'] ?? '';
        final predictedTrend = data['predictedTrend'] ?? 'stable';
        final predictedPriceRange = data['predictedPriceRange'] ?? 'N/A';
        final predictionRationale = data['predictionRationale'] ?? '';
        final List<dynamic> news = data['news'] ?? [];
        final timestampStr = data['timestamp'] as String?;

        Color sentimentColor;
        IconData sentimentIcon;
        if (sentiment == 'bullish') {
          sentimentColor = Colors.green;
          sentimentIcon = Icons.trending_up;
        } else if (sentiment == 'bearish') {
          sentimentColor = Colors.red;
          sentimentIcon = Icons.trending_down;
        } else {
          sentimentColor = Colors.orange;
          sentimentIcon = Icons.trending_flat;
        }

        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (timestampStr != null) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Last Updated: ${_formatAITimestamp(timestampStr)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: _buildInsightMetricCard(
                      title: 'Market Sentiment',
                      value: sentiment.toString().toUpperCase(),
                      subtitle: 'Score: $sentimentScore',
                      icon: sentimentIcon,
                      color: sentimentColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildInsightMetricCard(
                      title: 'Predicted Trend',
                      value: predictedTrend.toString().toUpperCase(),
                      subtitle: 'Range: ₹ $predictedPriceRange',
                      icon: predictedTrend == 'upward'
                          ? Icons.arrow_circle_up
                          : (predictedTrend == 'downward'
                              ? Icons.arrow_circle_down
                              : Icons.arrow_circle_right_outlined),
                      color: predictedTrend == 'upward'
                          ? Colors.green
                          : (predictedTrend == 'downward' ? Colors.red : Colors.orange),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (sentimentSummary.isNotEmpty) ...[
                const Text(
                  'Market Summary',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 6),
                Text(
                  sentimentSummary,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 16),
              ],
              if (predictionRationale.isNotEmpty) ...[
                Card(
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  color: Colors.grey.withValues(alpha: 0.03),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
                  ),
                  child: ExpansionTile(
                    title: const Text(
                      'AI Analysis & Rationale',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    expandedAlignment: Alignment.topLeft,
                    children: [
                      Text(
                        predictionRationale,
                        style: const TextStyle(fontSize: 13, height: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (news.isNotEmpty) ...[
                ExpansionTile(
                  title: Text(
                    'Latest Analyzed News (${news.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  tilePadding: EdgeInsets.zero,
                  children: news.map((item) {
                    final title = item['title'] ?? '';
                    final source = item['source'] ?? '';
                    final pubDate = item['pubDate'] ?? '';
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      elevation: 0,
                      color: Colors.grey.withValues(alpha: 0.03),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
                      ),
                      child: ListTile(
                        dense: true,
                        title: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
                        ),
                        subtitle: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              source,
                              style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              pubDate,
                              style: const TextStyle(color: Colors.grey, fontSize: 9),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
              ],
              _buildGenerateAIButton(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGoldChitAdviceContent() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('gold_chit_advice').doc('latest').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final data = snapshot.data?.data() as Map<String, dynamic>?;

        if (data == null) {
          return Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                const Icon(Icons.monetization_on_outlined, size: 48, color: Colors.amber),
                const SizedBox(height: 12),
                const Text(
                  'No Chit Advice Generated Yet',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Get Gemini to analyze price trends for your ₹10,000 monthly chit payment (1st - 25th) and predict the lowest rate day.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 16),
                _buildGenerateChitButton(),
              ],
            ),
          );
        }

        final recommendation = data['recommendation'] ?? 'WAIT';
        final shortReason = data['shortReason'] ?? '';
        final fullAnalysis = data['fullAnalysis'] ?? '';
        final timestampStr = data['timestamp'] as String?;

        Color recColor = recommendation == 'BUY' ? Colors.green : Colors.orange;
        IconData recIcon = recommendation == 'BUY' ? Icons.check_circle : Icons.pause_circle_filled;

        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (timestampStr != null) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Last Updated: ${_formatAITimestamp(timestampStr)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.15)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Monthly Strategy (1st - 25th):\nGoal is to pay your ₹10k monthly chit on the day with the lowest gold price.',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: recColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: recColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(recIcon, color: recColor, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "TODAY'S CHIT RECOMMENDATION",
                            style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            recommendation == 'BUY' ? 'PAY TODAY' : 'WAIT & WATCH',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: recColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (shortReason.isNotEmpty) ...[
                const Text(
                  'Daily Alert Preview',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 6),
                Text(
                  '"$shortReason"',
                  style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 16),
              ],
              if (fullAnalysis.isNotEmpty) ...[
                Card(
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  color: Colors.grey.withValues(alpha: 0.03),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
                  ),
                  child: ExpansionTile(
                    title: const Text(
                      'Gemini Strategy Analysis',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    expandedAlignment: Alignment.topLeft,
                    children: [
                      Text(
                        fullAnalysis,
                        style: const TextStyle(fontSize: 13, height: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Card(
                color: Colors.grey.withValues(alpha: 0.02),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Icon(Icons.notifications_active_outlined, color: Colors.amber, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Daily Reminder Scheduled: You will receive an alert at 11:01 AM IST every day with these insights.',
                          style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _buildGenerateChitButton(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInsightMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
              ),
              Icon(icon, color: color, size: 16),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildGenerateAIButton() {
    if (!_askGeminiEnabled) return const SizedBox.shrink();
    return _isGeneratingAI
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(8.0),
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 8),
                  Text('Gemini is analyzing market news & prices...', style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
          )
        : ElevatedButton.icon(
            onPressed: _generateAIInsights,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo.shade800,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Ask Gemini to Forecast Prices'),
          );
  }

  Widget _buildGenerateChitButton() {
    if (!_askGeminiEnabled) return const SizedBox.shrink();
    return _isGeneratingChit
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(8.0),
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 8),
                  Text('Gemini is calculating optimal buy days...', style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
          )
        : ElevatedButton.icon(
            onPressed: _generateChitAdvice,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade800,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.insights),
            label: const Text('Recalculate Buy Strategy'),
          );
  }

  Future<void> _generateAIInsights() async {
    setState(() => _isGeneratingAI = true);
    try {
      final res = await _goldService.generateAIInsights();
      if (mounted) {
        if (res.containsKey('error')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ AI Forecast Failed: ${res['error']}'),
              backgroundColor: Colors.red,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ AI Predictions generated successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error calling AI service: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingAI = false);
      }
    }
  }

  Future<void> _generateChitAdvice() async {
    setState(() => _isGeneratingChit = true);
    try {
      final res = await _goldService.generateChitAdvice();
      if (mounted) {
        if (res.containsKey('error')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Failed to calculate strategy: ${res['error']}'),
              backgroundColor: Colors.red,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Gold Chit strategy updated!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error calling advice service: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingChit = false);
      }
    }
  }
}
