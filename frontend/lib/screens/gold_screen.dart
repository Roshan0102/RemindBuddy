
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
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
      // Fetch History
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

  Future<void> _fetchPrice() async {
    setState(() => _isLoading = true);
    final service = GoldPriceService();
    // Simulate background fetch logic here or call service
    // We reuse the verify logic which saves to DB
    final result = await service.checkAndNotifyGoldPriceChange();
    if (result != null && result['price'] != null) {
       // Reload data
       await _loadData();
    } else {
       if (mounted) setState(() => _isLoading = false);
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Could not fetch latest price. Check internet.')),
         );
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
            icon: const Icon(Icons.refresh),
            onPressed: _fetchPrice,
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
                     'Recent History (Last 10 Days)',
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
                   _buildChart(),
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
    
    Color diffColor = Colors.grey;
    IconData diffIcon = Icons.remove;
    String diffText = "No Change";
    
    if (diff > 0) {
      diffColor = Colors.red;
      diffIcon = Icons.arrow_upward;
      diffText = "+₹${diff.toStringAsFixed(0)}";
    } else if (diff < 0) {
      diffColor = Colors.green;
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
            const Text('Today\'s Gold Rate (22K)', style: TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 8),
            Text(
              '₹ ${price.toStringAsFixed(0)}', 
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.amber),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(diffIcon, color: diffColor, size: 20),
                const SizedBox(width: 4),
                Text(
                  diffText,
                  style: TextStyle(color: diffColor, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  ' (vs Previous)',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
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
      child: DataTable(
        columnSpacing: 20,
        columns: const [
          DataColumn(label: Text('Date/Time')),
          DataColumn(label: Text('Price (22K)')),
          DataColumn(label: Text('City')),
        ],
        rows: _history.map((price) {
          return DataRow(cells: [
            DataCell(Text(price.date)), // date might contain timestamp part now so we might format it
            DataCell(Text('₹ ${price.price22k.toStringAsFixed(0)}')),
            DataCell(Text(price.city)),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _buildChart() {
    if (_history.length < 2) return const SizedBox(height: 200, child: Center(child: Text("Not enough data for chart")));

    // Sort for chart (oldest first)
    final sortedHistory = List<GoldPrice>.from(_history);
    sortedHistory.sort((a, b) => a.date.compareTo(b.date));

    // Map to FlSpots
    // We use index as X axis for simplicity in this view
    List<FlSpot> spots = [];
    double minPrice = double.infinity;
    double maxPrice = double.negativeInfinity;

    for (int i = 0; i < sortedHistory.length; i++) {
        final p = sortedHistory[i].price22k;
        if (p < minPrice) minPrice = p;
        if (p > maxPrice) maxPrice = p;
        spots.add(FlSpot(i.toDouble(), p));
    }
    
    // Add buffer to Y axis
    minPrice = (minPrice - 500).roundToDouble();
    maxPrice = (maxPrice + 500).roundToDouble();

    return SizedBox(
      height: 250,
      child: LineChart(
        LineChartData(
          minY: minPrice,
          maxY: maxPrice,
          lineTouchData: const LineTouchData(enabled: true),
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
               sideTitles: SideTitles(
                 showTitles: true,
                 getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index >= 0 && index < sortedHistory.length) {
                       // Show partial date
                       final date = sortedHistory[index].date;
                       // Extract DD/MM if possible or just show short
                       try {
                         // date format from DB: "2024-05-10T..."
                         // if it is full iso string
                         final dt = DateTime.parse(date.contains("T") ? date : "$date 00:00:00");
                         return Padding(
                           padding: const EdgeInsets.only(top: 4.0),
                           child: Text(DateFormat('dd/MM').format(dt), style: const TextStyle(fontSize: 10)),
                         );
                       } catch (e) {
                         return const Text('');
                       }
                    }
                    return const Text('');
                 },
                 interval: 1, // Show every point if few, or skip if many
                 reservedSize: 22,
               )
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                   return Text(value.toStringAsFixed(0), style: const TextStyle(fontSize: 10, color: Colors.grey));
                },
                interval: (maxPrice - minPrice) / 4,
                reservedSize: 40,
              )
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: Colors.amber,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.amber.withOpacity(0.2), // Deprecated .withOpacity for Color is OK in older FL Chart? No, wait.
                // Latest Flutter uses .withValues but .withOpacity is usually still there marked deprecated slightly. I'll use simple Opacity.
              ),
            ),
          ],
        ),
      ),
    );
  }
}
