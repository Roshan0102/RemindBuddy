
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';
import '../services/gold_price_service.dart';
import '../services/storage_service.dart';
import '../models/gold_price.dart';
import 'package:shared_preferences/shared_preferences.dart';
// import '../services/gold_scheduler_service.dart';

class GoldScreen extends StatefulWidget {
  const GoldScreen({super.key});

  @override
  State<GoldScreen> createState() => _GoldScreenState();
}

class _GoldScreenState extends State<GoldScreen> {
  final GoldPriceService _goldService = GoldPriceService();
  bool _isFetching = false;
  String _lastLog = "No logs yet. Click 'Refresh' to fetch price.";
  Map<String, dynamic>? _lastFullData;

  TimeOfDay _morningTime = const TimeOfDay(hour: 11, minute: 0);
  TimeOfDay _eveningTime = const TimeOfDay(hour: 19, minute: 0);

  @override
  void initState() {
    super.initState();
  }

  Future<void> _fetchPrice() async {
    if (_isFetching) return;
    setState(() => _isFetching = true);
    
    try {
      final result = await _goldService.triggerForceFetch();
      if (mounted) {
        if (result.containsKey('error')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Fetch Error: ${result['error']}'), backgroundColor: Colors.red),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Manual fetch completed! Update will mirror shortly.')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isFetching = false);
    }
  }

  void _showDebugLog() async {
    final log = await _goldService.getLatestFetchLog();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Last Fetch Diagnostics (Debug)'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        content: Container(
          width: double.maxFinite,
          constraints: const BoxConstraints(maxHeight: 400),
          child: log == null 
            ? const Text('No execution logs found.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Status: ${log['status']}', style: TextStyle(fontWeight: FontWeight.bold, color: log['status'] == 'SUCCESS' ? Colors.green : Colors.red)),
                  Text('Timestamp: ${log['timestamp']}'),
                  Text('Primary Source: ${log['sourceUsed'] ?? 'N/A'}'),
                  const Divider(),
                  const Text('Individual Source Results:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...(log['logs'] as List? ?? []).map((l) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• $l', style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                  )),
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
                          _sourceRow('TOI Chennai', data['times_of_india']),
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

  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Global Price History?'),
        content: const Text('This will delete all price history from Firestore. This affects ALL users.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isFetching = true);
      await _goldService.clearGoldPriceHistory();
      if (mounted) {
        setState(() => _isFetching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Global gold price history cleared.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GoldPrice>>(
      stream: _goldService.getGlobalGoldPricesStream(),
      builder: (context, snapshot) {
        final history = snapshot.data ?? [];
        final currentPrice = history.isNotEmpty ? history.first : null;
        final priceDiff = currentPrice != null ? currentPrice.priceChange : 0.0;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Gold Rates (22K)'),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_forever),
                onPressed: _clearAllData,
                tooltip: 'Clear History',
              ),
              IconButton(
                icon: const Icon(Icons.compare_arrows),
                onPressed: _showSourceChecker,
                tooltip: 'Check Sources',
              ),
              IconButton(
                icon: const Icon(Icons.bug_report),
                onPressed: _showDebugLog,
                tooltip: 'Debug Log',
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _fetchPrice,
                tooltip: 'Refresh',
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
                          const Text(
                            'Recent History (Live Mirror)',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          _buildHistoryTable(history),
                          const SizedBox(height: 24),
                          const Text(
                            'Price Trend',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
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
      diffColor = Colors.green;
      diffIcon = Icons.arrow_upward;
      diffText = "+₹${diff.toStringAsFixed(0)}";
    } else if (diff < 0) {
      diffColor = Colors.red;
      diffIcon = Icons.arrow_downward;
      diffText = "-₹${diff.abs().toStringAsFixed(0)}";
    }
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const Text('Latest Gold Rate (22K)', style: TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 8),
            Text(
              '₹ ${price.toStringAsFixed(0)}', 
              style: TextStyle(
                fontSize: 48, 
                fontWeight: FontWeight.bold, 
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
             if (diff != 0) 
               Row(
                 mainAxisAlignment: MainAxisAlignment.center,
                 children: [
                   Icon(diffIcon, color: diffColor, size: 24),
                   const SizedBox(width: 4),
                   Text(
                     diffText,
                     style: TextStyle(color: diffColor, fontWeight: FontWeight.bold, fontSize: 18),
                   ),
                   Text(
                     ' (vs Previous)',
                     style: TextStyle(color: Colors.grey[600], fontSize: 14),
                   ),
                 ],
               ),
            const SizedBox(height: 8),
            Text(
              'Updated: ${_formatDate(currentPrice.timestamp)} via ${currentPrice.source}', 
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryTable(List<GoldPrice> history) {
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 20,
          columns: const [
            DataColumn(label: Text('Date & Time')),
            DataColumn(label: Text('Price (22K)')),
            DataColumn(label: Text('Change')),
            DataColumn(label: Text('Source')),
          ],
          rows: history.map((price) {
            final change = price.priceChange;
            return DataRow(cells: [
              DataCell(Text(_formatDate(price.timestamp))),
              DataCell(Text('₹ ${price.price.toStringAsFixed(0)}')),
              DataCell(
                change != 0
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                           Icon(
                             change > 0 ? Icons.arrow_upward : Icons.arrow_downward,
                             size: 16,
                             color: change > 0 ? Colors.green : Colors.red,
                           ),
                           Text(
                             '₹${change.abs().toStringAsFixed(0)}',
                             style: TextStyle(
                               color: change > 0 ? Colors.green : Colors.red,
                             ),
                           ),
                        ],
                      )
                    : const Text('-'),
              ),
              DataCell(Text(price.source, style: const TextStyle(fontSize: 10))),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildModernChart(List<GoldPrice> history) {
    if (history.length < 2) return const SizedBox.shrink();

    // Chart needs chronological order
    final sortedHistory = List<GoldPrice>.from(history).reversed.toList();

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          height: 250,
          child: SfCartesianChart(
            primaryXAxis: CategoryAxis(
              majorGridLines: const MajorGridLines(width: 0),
              labelRotation: -45,
              labelStyle: const TextStyle(fontSize: 8),
            ),
            primaryYAxis: NumericAxis(
              numberFormat: NumberFormat.currency(symbol: '₹', decimalDigits: 0),
              axisLine: const AxisLine(width: 0),
            ),
            tooltipBehavior: TooltipBehavior(enable: true),
            series: <CartesianSeries>[
              AreaSeries<GoldPrice, String>(
                dataSource: sortedHistory,
                xValueMapper: (GoldPrice p, _) => _formatDate(p.timestamp),
                yValueMapper: (GoldPrice p, _) => p.price,
                color: Colors.amber.withOpacity(0.3),
                borderColor: Colors.amber,
                borderWidth: 2,
                markerSettings: const MarkerSettings(isVisible: true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScheduleInfo() {
    return Card(
      color: Colors.blue.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.schedule, color: Colors.blue),
                SizedBox(width: 8),
                Text('Notification Schedule (IST)', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            _scheduleRow('11:00 AM', 'Daily rate update (Always)'),
            _scheduleRow('07:00 PM', 'Evening check (Only if price differs)'),
          ],
        ),
      ),
    );
  }

  Widget _scheduleRow(String time, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        children: [
          Text(time, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 12)),
          const SizedBox(width: 8),
          Expanded(child: Text(desc, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      return DateFormat('dd/MM HH:mm').format(dt);
    } catch (e) {
      return dateStr;
    }
  }
}
