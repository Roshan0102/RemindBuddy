import 'package:flutter/material.dart';
import '../services/gold_price_service.dart';
import '../services/storage_service.dart';

/// Test screen to verify gold price fetching works
class GoldPriceTestScreen extends StatefulWidget {
  const GoldPriceTestScreen({super.key});

  @override
  State<GoldPriceTestScreen> createState() => _GoldPriceTestScreenState();
}

class _GoldPriceTestScreenState extends State<GoldPriceTestScreen> {
  final GoldPriceService _goldService = GoldPriceService();
  final StorageService _storage = StorageService();
  
  String _status = 'Ready to fetch';
  bool _isLoading = false;
  String? _price22k;
  String? _date;

  Future<void> _testFetchPrice() async {
    setState(() {
      _isLoading = true;
      _status = 'Fetching gold price from goodreturns.in (WebView)...';
    });

    try {
      final goldPrice = await _goldService.fetchCurrentGoldPrice();
      
      if (goldPrice != null) {
        // Save to database
        await _storage.saveGoldPrice(goldPrice);
        
        if (mounted) {
          setState(() {
            _status = '✅ Successfully fetched and saved!';
            _price22k = '₹${goldPrice.price22k.toStringAsFixed(0)}';
            _date = goldPrice.date;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _status = '❌ Failed to fetch price. Check console.';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = '❌ Error: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _testFetchWithFallback() async {
    setState(() {
      _isLoading = true;
      _status = 'Fetching with fallback...';
    });

    try {
      final goldPrice = await _goldService.fetchGoldPriceWithFallback();
      await _storage.saveGoldPrice(goldPrice);
      
      if (mounted) {
        setState(() {
          _status = '✅ Fetched (may be mock data)';
          _price22k = '₹${goldPrice.price22k.toStringAsFixed(0)}';
          _date = goldPrice.date;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = '❌ Error: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _viewSavedPrices() async {
    final prices = await _storage.getGoldPrices(limit: 10);
    
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Saved Gold Prices'),
        content: SizedBox(
          width: double.maxFinite,
          child: prices.isEmpty
              ? const Text('No prices saved yet')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: prices.length,
                  itemBuilder: (context, index) {
                    final price = prices[index];
                    return ListTile(
                      title: Text('₹${price.price22k.toStringAsFixed(0)}'),
                      subtitle: Text(price.date),
                    );
                  },
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gold Price Test'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Icon(Icons.monetization_on, size: 64, color: Colors.amber),
                    const SizedBox(height: 16),
                    Text(
                      _status,
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    if (_isLoading) ...[
                      const SizedBox(height: 16),
                      const CircularProgressIndicator(),
                    ],
                    if (_price22k != null) ...[
                      const SizedBox(height: 24),
                      const Text('22K Gold Price', style: TextStyle(fontSize: 12)),
                      Text(
                        _price22k!,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                      if (_date != null) ...[
                        const SizedBox(height: 8),
                        Text('Date: $_date', style: const TextStyle(fontSize: 12)),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _testFetchPrice,
              icon: const Icon(Icons.download),
              label: const Text('Test Fetch from Website'),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _testFetchWithFallback,
              icon: const Icon(Icons.backup),
              label: const Text('Test Fetch with Fallback'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _viewSavedPrices,
              icon: const Icon(Icons.history),
              label: const Text('View Saved Prices'),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            const Text(
              'Instructions:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '1. Click "Test Fetch from Website" to scrape goodreturns.in\n'
              '2. Check the console for detailed logs\n'
              '3. If it fails, try "Test Fetch with Fallback" for mock data\n'
              '4. View saved prices to see database storage working',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
