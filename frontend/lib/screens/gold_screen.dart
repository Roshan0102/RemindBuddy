
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';
import '../services/gold_price_service.dart';
import '../services/storage_service.dart';
import '../models/gold_price.dart';

class GoldScreen extends StatefulWidget {
  const GoldScreen({super.key});

  @override
  State<GoldScreen> createState() => _GoldScreenState();
}

class _GoldScreenState extends State<GoldScreen> {
  GoldPrice? _currentPrice;
  List<GoldPrice> _history = [];
  bool _isLoading = true;
  double? _priceDiff;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final storage = StorageService();
      // Fetch latest from DB
      _currentPrice = await storage.getLatestGoldPrice();
      // Fetch History (last 10 entries)
      _history = await storage.getGoldPriceHistory(limit: 10);
      
      // Calculate Diff
      final double? prev = await storage.getPreviousGoldPrice();
      if (_currentPrice != null && prev != null) {
        _priceDiff = _currentPrice!.price22k - prev;
      }
      
      // If no current price today, try fetch
      if (_currentPrice == null) {
        await _fetchPrice();
      }
    } catch (e) {
      print("Error loading gold data: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _lastLog = "No logs yet. Click 'Refresh' to fetch price.";

  Future<void> _fetchPrice() async {
    setState(() => _isLoading = true);
    try {
      final goldService = GoldPriceService();
      final storage = StorageService();
      
      // Fetch current price with debug info
      final result = await goldService.fetchCurrentGoldPrice();
      final newPrice = result['price'] as GoldPrice?;
      final method = result['method'];
      final debug = result['debug'];
      
      _lastLog = result['log'] ?? "No log returned";
      print('📊 Fetch method: $method');
      print('🔍 Debug: $debug');
      
      if (newPrice != null) {
        // Get latest price from database
        final latestPrice = await storage.getLatestGoldPrice();
        
        if (latestPrice != null && 
            latestPrice.date == newPrice.date &&
            (newPrice.price22k - latestPrice.price22k).abs() < 1.0) {
          // Same day, price hasn't changed significantly - just update timestamp
          print('✓ Price unchanged - Updating timestamp only');
          // Don't add new row, just refresh UI
        } else {
          // Price changed or new day - save new entry
          await storage.saveGoldPrice(newPrice);
          print('✅ New price saved: ₹${newPrice.price22k}');
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Fetched via $method: ₹${newPrice.price22k.toStringAsFixed(0)}'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Failed to fetch: $debug'),
              backgroundColor: Colors.red,
              action: SnackBarAction(
                label: 'Details',
                textColor: Colors.white,
                onPressed: _showDebugLog,
              ),
            ),
          );
        }
      }
    } catch (e) {
      _lastLog += "\nCRITICAL ERROR: $e";
      print('Error fetching price: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // Reload data
      await _loadData();
    }
  }

  void _showDebugLog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fetching Logs'),
        content: Container(
          width: double.maxFinite,
          constraints: const BoxConstraints(maxHeight: 400),
          child: SingleChildScrollView(
            child: SelectableText(
              _lastLog,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
            TextButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('Copy Log'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _lastLog));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Log copied to clipboard')),
                );
              },
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
        ],
      ),
    );
  }


  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Gold Data?'),
        content: const Text('This will delete all gold price history. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final storage = StorageService();
      final db = await storage.database;
      await db.delete('gold_prices');
      await db.delete('gold_prices_history');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ All gold price data cleared')),
        );
        await _loadData();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gold Rates (22K)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever),
            onPressed: _clearAllData,
            tooltip: 'Clear All Data',
          ),
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: _showDebugLog,
            tooltip: 'Show Debug Log',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchPrice,
            tooltip: 'Refresh Price',
          ),
        ],
      ),
      body: _isLoading && _currentPrice == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                   _buildCurrentPriceCard(),
                   const SizedBox(height: 24),
                   const Text(
                     'Recent History (Last 10 Updates)',
                     style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                   ),
                   const SizedBox(height: 8),
                   _buildHistoryTable(),
                   const SizedBox(height: 24),
                   const Text(
                     'Price Trend',
                     style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                   ),
                   const SizedBox(height: 16),
                   _buildModernChart(),
                   const SizedBox(height: 16),
                   _buildScheduleInfo(),
                ],
              ),
            ),
    );
  }

  Widget _buildCurrentPriceCard() {
    if (_currentPrice == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No Gold Price Data Available'),
        ),
      );
    }
    
    final price = _currentPrice!.price22k;
    final diff = _priceDiff ?? 0;
    
    // Green for increase, Red for decrease (Issue #4)
    Color diffColor = Colors.grey;
    IconData diffIcon = Icons.remove;
    String diffText = "";
    
    if (diff > 0) {
      diffColor = Colors.green;  // Price increased = good
      diffIcon = Icons.arrow_upward;
      diffText = "+₹${diff.toStringAsFixed(0)}";
    } else if (diff < 0) {
      diffColor = Colors.red;  // Price decreased = bad
      diffIcon = Icons.arrow_downward;
      diffText = "₹${diff.toStringAsFixed(0)}";
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
                color: Theme.of(context).colorScheme.onSurface,  // Dark color matching background
              ),
            ),
            const SizedBox(height: 8),
             if (diff != 0)  // Only show if there's a change
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
              'Updated: ${_currentPrice!.date}', 
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryTable() {
    if (_history.isEmpty) return const Text('No history available');

    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 20,
          columns: const [
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Price (22K)')),
            DataColumn(label: Text('Change')),
          ],
          rows: List.generate(_history.length, (index) {
            final price = _history[index];
            double? change;
            if (index < _history.length - 1) {
              change = price.price22k - _history[index + 1].price22k;
            }
            
            return DataRow(cells: [
              DataCell(Text(_formatDate(price.date))),
              DataCell(Text('₹ ${price.price22k.toStringAsFixed(0)}')),
              DataCell(
                change != null
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                           Icon(
                             change > 0 ? Icons.arrow_upward : change < 0 ? Icons.arrow_downward : Icons.remove,
                             size: 16,
                             color: change > 0 ? Colors.green : change < 0 ? Colors.red : Colors.grey,  // Green for increase
                           ),
                           Text(
                             change != 0 ? '₹${change.abs().toStringAsFixed(0)}' : '-',
                             style: TextStyle(
                               color: change > 0 ? Colors.green : change < 0 ? Colors.red : Colors.grey,  // Green for increase
                             ),
                           ),
                        ],
                      )
                    : const Text('-'),
              ),
            ]);
          }),
        ),
      ),
    );
  }

  Widget _buildModernChart() {
    if (_history.length < 2) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text("Not enough data for chart")),
      );
    }

    // Sort for chart (oldest first)
    final sortedHistory = List<GoldPrice>.from(_history);
    sortedHistory.sort((a, b) => a.date.compareTo(b.date));

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          height: 300,
          child: SfCartesianChart(
            primaryXAxis: CategoryAxis(
              majorGridLines: const MajorGridLines(width: 0),
              labelRotation: -45,
            ),
            primaryYAxis: NumericAxis(
              numberFormat: NumberFormat.currency(symbol: '₹', decimalDigits: 0),
              axisLine: const AxisLine(width: 0),
              majorTickLines: const MajorTickLines(size: 0),
            ),
            tooltipBehavior: TooltipBehavior(
              enable: true,
              format: 'point.x : ₹point.y',
            ),
            series: <CartesianSeries>[
              // Area series for filled chart
              AreaSeries<GoldPrice, String>(
                dataSource: sortedHistory,
                xValueMapper: (GoldPrice price, _) => _formatDate(price.date),
                yValueMapper: (GoldPrice price, _) => price.price22k,
                name: '22K Gold',
                color: Colors.amber.withOpacity(0.5),
                borderColor: Colors.amber,
                borderWidth: 3,
                gradient: LinearGradient(
                  colors: [
                    Colors.amber.withOpacity(0.7),
                    Colors.amber.withOpacity(0.1),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                markerSettings: const MarkerSettings(
                  isVisible: true,
                  shape: DataMarkerType.circle,
                  borderColor: Colors.amber,
                  borderWidth: 2,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScheduleInfo() {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.schedule, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  'Auto-Update Schedule',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildScheduleRow('11:00 AM IST', 'Daily price update (always saved)'),
            const SizedBox(height: 8),
            _buildScheduleRow('7:00 PM IST', 'Price check (saved only if changed)'),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleRow(String time, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.blue.shade700,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            time,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            description,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
        ),
      ],
    );
  }

  String _formatDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr.contains("T") ? dateStr : "$dateStr 00:00:00");
      return DateFormat('dd/MM HH:mm').format(dt);
    } catch (e) {
      return dateStr.substring(0, dateStr.length > 10 ? 10 : dateStr.length);
    }
  }
}
