import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import '../models/gold_price.dart';
import 'package:intl/intl.dart';

class GoldPriceService {
  static final GoldPriceService _instance = GoldPriceService._internal();
  factory GoldPriceService() => _instance;
  GoldPriceService._internal();

  static const String baseUrl = 'https://www.goodreturns.in/gold-rates/chennai.html';

  /// Fetch current gold price from goodreturns.in
  /// Uses proper HTML parsing to extract price from <span id="22k-price">
  Future<GoldPrice?> fetchCurrentGoldPrice() async {
    try {
      print('🔍 Fetching gold price from: $baseUrl');
      
      final response = await http.get(
        Uri.parse(baseUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 10; SM-G973F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.5',
        },
      );
      
      if (response.statusCode == 200) {
        print('✅ Successfully fetched page (${response.body.length} bytes)');
        
        // Parse HTML
        final document = html_parser.parse(response.body);
        
        // Method 1: Look for <span id="22k-price">
        final price22kElement = document.getElementById('22k-price');
        
        if (price22kElement != null) {
          final priceText = price22kElement.text.trim();
          print('📊 Found 22K price element: $priceText');
          
          // Extract number from text like "₹14,600" or "14,600"
          final priceStr = priceText.replaceAll(RegExp(r'[₹,\s]'), '');
          final price22k = double.tryParse(priceStr);
          
          if (price22k != null && price22k > 1000 && price22k < 100000) {
            print('💰 Parsed 22K price: ₹$price22k');
            
            return GoldPrice(
              date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
              price22k: price22k,
              price24k: 0.0, // Not fetching 24K as per user request
              city: 'Chennai',
            );
          } else {
            print('⚠️ Parsed price seems invalid: $price22k');
          }
        } else {
          print('⚠️ Element with id="22k-price" not found');
        }
        
        // Method 2: Fallback - search for class="gold-common-head" and nearby price
        print('🔄 Trying fallback method...');
        
        final goldCommonHeads = document.querySelectorAll('.gold-common-head');
        for (var element in goldCommonHeads) {
          final text = element.text.trim();
          print('   Checking element: $text');
          
          if (text.contains('22K') || text.contains('22k')) {
            // Look for sibling or parent with price
            final parent = element.parent;
            if (parent != null) {
              final priceSpans = parent.querySelectorAll('span');
              for (var span in priceSpans) {
                final spanText = span.text.trim();
                // Look for price pattern
                if (spanText.contains('₹') || RegExp(r'^\d{2,5}$').hasMatch(spanText.replaceAll(',', ''))) {
                  final priceStr = spanText.replaceAll(RegExp(r'[₹,\s]'), '');
                  final price = double.tryParse(priceStr);
                  if (price != null && price > 1000 && price < 100000) {
                    print('💰 Found 22K price via fallback: ₹$price');
                    return GoldPrice(
                      date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
                      price22k: price,
                      price24k: 0.0,
                      city: 'Chennai',
                    );
                  }
                }
              }
            }
          }
        }
        
        print('❌ Could not find gold price in HTML');
        return null;
      }
      
      print('❌ Failed to fetch gold price: HTTP ${response.statusCode}');
      return null;
    } catch (e, stackTrace) {
      print('❌ Error fetching gold price: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Fetch gold price with fallback to mock data for testing
  Future<GoldPrice> fetchGoldPriceWithFallback() async {
    final price = await fetchCurrentGoldPrice();
    
    if (price != null) {
      return price;
    }
    
    print('⚠️ Using fallback mock data');
    // Fallback to mock data for testing
    return GoldPrice(
      date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
      price22k: 14600.0,
      price24k: 15928.0,
      city: 'Chennai',
    );
  }

  /// Generate mock historical data for testing
  /// In production, this would fetch from backend/API
  List<GoldPrice> generateMockHistoricalData() {
    final List<GoldPrice> prices = [];
    final DateTime today = DateTime.now();
    
    // Base price with some variation
    double basePrice = 14600.0;
    
    for (int i = 9; i >= 0; i--) {
      final date = today.subtract(Duration(days: i));
      // Add some random variation
      final variation = (i % 3 - 1) * 50.0; // -50, 0, or +50
      final price = basePrice + variation;
      
      prices.add(GoldPrice(
        date: DateFormat('yyyy-MM-dd').format(date),
        price22k: price,
        price24k: price * 1.09, // 24k is typically ~9% higher
        city: 'Chennai',
      ));
      
      basePrice = price; // Use this as base for next day
    }
    
    return prices;
  }
}

