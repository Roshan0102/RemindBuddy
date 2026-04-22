import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
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
      final price = GoldPrice.fromJson(doc, snapshot.docs.first.id);

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

  Stream<List<GoldPrice>> getGlobalGoldPricesStream({int limit = 30}) {
    return _db
        .collection('global_gold_prices')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => GoldPrice.fromJson(doc.data(), doc.id)).toList();
    });
  }

  Future<Map<String, dynamic>?> checkAndNotifyGoldPriceChange() async {
    return await fetchCurrentGoldPrice();
  }

  // --- Diagnostic & Manual Tools ---

  Future<Map<String, dynamic>> checkAllSourcesManual() async {
    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('checkGoldSources');
      final result = await callable.call();
      return Map<String, dynamic>.from(result.data as Map);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> triggerForceFetch() async {
    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('forceGoldFetch');
      final result = await callable.call();
      return Map<String, dynamic>.from(result.data as Map);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>?> getLatestFetchLog() async {
    try {
      final doc = await _db.collection('gold_fetch_logs').doc('latest').get();
      return doc.data();
    } catch (e) {
      return null;
    }
  }

  Future<void> clearGoldPriceHistory() async {
    final batch = _db.batch();
    final snap = await _db.collection('global_gold_prices').get();
    for (var doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
