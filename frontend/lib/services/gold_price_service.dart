import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/gold_price.dart';

class GoldPriceService {
  static final GoldPriceService _instance = GoldPriceService._internal();
  factory GoldPriceService() => _instance;
  GoldPriceService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<Map<String, dynamic>> fetchCurrentGoldPrice() async {
    try {
      // Query the global_gold_prices collection
      final snapshot = await _db
          .collection('global_gold_prices')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        return {
          'price': null,
          'method': 'cloud_firestore_empty',
          'debug': 'No gold prices found in the global collection',
          'log': 'Failed to fetch from Cloud',
        };
      }

      final doc = snapshot.docs.first.data();
      
      final price = GoldPrice(
        date: doc['date'] ?? DateFormat('yyyy-MM-dd').format(DateTime.now()),
        timestamp: doc['timestamp'] ?? DateTime.now().toIso8601String(),
        price: (doc['price'] ?? 0).toDouble(),
      );

      return {
        'price': price,
        'method': 'cloud_firestore',
        'debug': 'Fetched successfully from global_gold_prices',
        'fetchedTime': doc['fetchedTime'] ?? '',
        'log': '✅ Price fetched from Cloud Firestore',
        'full_data': doc
      };
    } catch (e) {
      return {
        'price': null,
        'method': 'cloud_firestore_exception',
        'debug': 'Service exception: $e',
        'log': '❌ Failed to fetch from Cloud: $e',
      };
    }
  }

  Future<Map<String, dynamic>?> checkAndNotifyGoldPriceChange() async {
    return await fetchCurrentGoldPrice();
  }
}
