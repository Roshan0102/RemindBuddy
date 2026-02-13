import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:intl/intl.dart';
import '../models/gold_price.dart';

class GoldPriceService {
  static final GoldPriceService _instance = GoldPriceService._internal();
  factory GoldPriceService() => _instance;
  GoldPriceService._internal();

  static const String baseUrl = 'https://www.goodreturns.in/gold-rates/chennai.html';

  /// Fetch current gold price from goodreturns.in
  /// Uses proper HTML parsing to extract price from <span id="22k-price">
  /// Uses HeadlessInAppWebView to bypass Cloudflare protection
  Future<GoldPrice?> fetchCurrentGoldPrice() async {
    // Only works on mobile platforms for now
    if (kIsWeb) return null;

    final Completer<GoldPrice?> completer = Completer<GoldPrice?>();
    
    // Create a HEADLESS webview (invisible browser)
    HeadlessInAppWebView? headlessWebView;
    
    try {
      print('🔍 Fetching gold price using Headless WebView from: $baseUrl');
      
      headlessWebView = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(baseUrl)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          cacheEnabled: false,
          userAgent: 'Mozilla/5.0 (Linux; Android 10; SM-G973F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        ),
        onLoadStop: (controller, url) async {
          print('✅ Headless WebView loaded page: $url');
          try {
            // Inject JavaScript to extract the price directly from the DOM
            // This runs inside the invisible browser page
            final String? priceText = await controller.evaluateJavascript(source: """
              (function() {
                try {
                  // Method 1: Look for ID '22k-price'
                  var el = document.getElementById('22k-price');
                  if (el) return el.innerText;
                  
                  // Method 2: Look for class 'gold-common-head'
                  var headers = document.querySelectorAll('.gold-common-head');
                  for (var i = 0; i < headers.length; i++) {
                     var text = headers[i].innerText;
                     if (text.includes('22K') || text.includes('22k')) {
                        // Find price in parent
                        var parent = headers[i].parentElement;
                        if (parent) {
                           // Try to find a span with a number pattern
                           var spans = parent.querySelectorAll('span');
                           for (var j = 0; j < spans.length; j++) {
                              var spanText = spans[j].innerText;
                              if (spanText.includes('₹') || /\\d{2,6}/.test(spanText)) {
                                 return spanText;
                              }
                           }
                        }
                     }
                  }
                  return null;
                } catch(e) { return null; }
              })();
            """);

            print('📊 Extracted text from WebView: $priceText');

            if (priceText != null && priceText.isNotEmpty) {
              // Extract number from text like "₹14,600" or "14,600"
              final priceStr = priceText.replaceAll(RegExp(r'[₹,\s]'), '');
              final price22k = double.tryParse(priceStr);
              
              if (price22k != null && price22k > 1000 && price22k < 100000) {
                print('💰 Parsed 22K price: ₹$price22k');
                completer.complete(GoldPrice(
                  date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
                  price22k: price22k,
                  price24k: 0.0,
                  city: 'Chennai',
                ));
              } else {
                print('⚠️ Parsed price seems invalid: $price22k');
                completer.complete(null);
              }
            } else {
              print('❌ Could not find gold price in WebView DOM');
              completer.complete(null);
            }
          } catch (e) {
            print('❌ Error evaluating JS in WebView: $e');
            completer.complete(null);
          }
        },
        onReceivedError: (controller, request, error) {
           print('❌ WebView Error: ${error.description}');
           if (!completer.isCompleted) completer.complete(null);
        },
        onReceivedHttpError: (controller, request, response) {
           print('❌ WebView HTTP Error: ${response.statusCode}');
           // Don't fail immediately, sometimes the page loads partial content
        },
      );

      // Run the headless webview
      await headlessWebView.run();
      
      // Set a timeout of 30 seconds
      return await completer.future.timeout(const Duration(seconds: 30), onTimeout: () {
        print('⏳ WebView timed out');
        return null;
      }).whenComplete(() {
        // Clean up
        headlessWebView?.dispose();
      });

    } catch (e) {
      print('❌ Error in Headless WebView service: $e');
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

