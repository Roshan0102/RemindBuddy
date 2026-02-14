import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:intl/intl.dart';
import '../models/gold_price.dart';

class GoldPriceService {
  static final GoldPriceService _instance = GoldPriceService._internal();
  factory GoldPriceService() => _instance;
  GoldPriceService._internal();

  static const String bankBazaarUrl = 'https://www.bankbazaar.com/gold-rate-chennai.html';
  static const String goodReturnsUrl = 'https://www.goodreturns.in/gold-rates/chennai.html';

  /// Fetch current gold price
  /// 1. Try BankBazaar (Primary) using Structure/Targeted Search
  /// 2. If fails, Try GoodReturns (Secondary) using ID Selector
  Future<Map<String, dynamic>> fetchCurrentGoldPrice() async {
    // Only works on mobile platforms for now
    if (kIsWeb) return {'price': null, 'method': 'web_not_supported', 'debug': 'Web platform not supported'};

    // 1. Try BankBazaar
    print('🔍 Attempting Primary Source: BankBazaar');
    final bbResult = await _fetchFromUrl(
      bankBazaarUrl, 
      'BankBazaar',
      _getBankBazaarScript()
    );
    
    if (bbResult['price'] != null) {
      return bbResult;
    }
    
    // 2. Try GoodReturns
    print('⚠️ BankBazaar failed (${bbResult['debug']}), attempting Secondary Source: GoodReturns');
    return await _fetchFromUrl(
      goodReturnsUrl,
      'GoodReturns', 
      _getGoodReturnsScript()
    );
  }

  Future<Map<String, dynamic>> _fetchFromUrl(String url, String sourceName, String jsScript) async {
    final Completer<Map<String, dynamic>> completer = Completer<Map<String, dynamic>>();
    HeadlessInAppWebView? headlessWebView;

    try {
      headlessWebView = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          cacheEnabled: false,
          userAgent: 'Mozilla/5.0 (Linux; Android 10; SM-G973F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        ),
        onLoadStop: (controller, loadedUrl) async {
          print('✅ Headless WebView loaded $sourceName: $loadedUrl');
          try {
            final String? priceText = await controller.evaluateJavascript(source: jsScript);
            print('📊 Extracted text from $sourceName: $priceText');

            if (priceText != null && priceText.isNotEmpty) {
              await _parseAndComplete(priceText, sourceName, completer);
            } else {
              if (!completer.isCompleted) {
                completer.complete({
                  'price': null,
                  'method': '${sourceName.toLowerCase()}_failed',
                  'debug': 'No text returned from JS extraction',
                });
              }
            }
          } catch (e) {
            if (!completer.isCompleted) {
              completer.complete({
                'price': null,
                'method': '${sourceName.toLowerCase()}_js_error',
                'debug': 'JS execution error: $e',
              });
            }
          }
        },
        onLoadError: (controller, url, code, message) {
           if (!completer.isCompleted) {
             completer.complete({
               'price': null,
               'method': '${sourceName.toLowerCase()}_load_error',
               'debug': 'WebView load error: $code - $message',
             });
           }
        },
      );

      await headlessWebView.run();
      
      return await completer.future.timeout(const Duration(seconds: 60), onTimeout: () {
        return {
          'price': null,
          'method': '${sourceName.toLowerCase()}_timeout',
          'debug': 'Timeout fetching from $sourceName',
        };
      }).whenComplete(() => headlessWebView?.dispose());
      
    } catch (e) {
      return {
        'price': null,
        'method': '${sourceName.toLowerCase()}_exception',
        'debug': 'Service exception: $e',
      };
    }
  }

  Future<void> _parseAndComplete(String priceText, String source, Completer<Map<String, dynamic>> completer) async {
    try {
      String textToParse = priceText;
      
      // Parse JSON if applicable
      String method = 'unknown';
      try {
         if (priceText.trim().startsWith('{') && priceText.contains('text')) {
            final clean = priceText.replaceAll(RegExp(r'[{}"]'), '');
            final parts = clean.split(',');
            for (var part in parts) {
              if (part.contains('text:')) textToParse = part.split('text:')[1].trim();
              if (part.contains('method:')) method = part.split('method:')[1].trim();
            }
         }
      } catch (e) {
        // use original text
      }

      // Regex to extract price
      final priceMatch = RegExp(r'(\d{1,3}(?:,\d{3})+|\d{4,})').firstMatch(textToParse);
      
      if (priceMatch != null) {
        final priceStr = priceMatch.group(0)!.replaceAll(',', '');
        final price22k = double.tryParse(priceStr);
        
        if (price22k != null && price22k > 1000 && price22k < 100000) {
          print('💰 Parsed 22K price from $source: ₹$price22k');
          if (!completer.isCompleted) {
            completer.complete({
              'price': GoldPrice(
                date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
                price22k: price22k,
                price24k: 0.0,
                city: 'Chennai',
              ),
              'method': '${source}_$method',
              'debug': 'Success from $source',
            });
          }
        } else {
           if (!completer.isCompleted) completer.complete({'price': null, 'method': 'invalid_range', 'debug': 'Price out of range: $price22k'});
        }
      } else {
         if (!completer.isCompleted) completer.complete({'price': null, 'method': 'parse_fail', 'debug': 'Regex failed on: $textToParse'});
      }
    } catch (e) {
      if (!completer.isCompleted) completer.complete({'price': null, 'method': 'parse_exception', 'debug': 'Exception: $e'});
    }
  }

  // Script for BankBazaar: Structure Search with Validation
  String _getBankBazaarScript() {
    return """
      (function() {
        try {
            const h2s = document.getElementsByTagName('h2');
            for (let i = 0; i < h2s.length; i++) {
                if (h2s[i].innerText.includes("Today's Gold Rate") || h2s[i].innerText.includes("Rate in Chennai")) {
                    const parent = h2s[i].parentElement;
                    if (parent) {
                        const priceSpan = parent.querySelector('.white-space-nowrap');
                        if (priceSpan) {
                            const text = priceSpan.innerText.trim();
                            // Client-side validation to filter out bad data like "14"
                            const match = text.match(/\\d{1,3}(,\\d{3})+|\\d{4,}/);
                            if (match) {
                                const val = parseFloat(match[0].replace(/,/g, ''));
                                if (val > 1000) {
                                    return JSON.stringify({text: text, method: 'structure_match'});
                                }
                            }
                        }
                    }
                }
            }
            return null;
        } catch(e) { return null; }
      })();
    """;
  }

  // Script for GoodReturns: ID Selector with Fallback
  String _getGoodReturnsScript() {
    return """
      (function() {
        try {
            // Priority 1: ID Selector
            const el = document.getElementById('22K-price');
            if (el && el.innerText) {
                 const text = el.innerText.trim();
                 const match = text.match(/\\d{1,3}(,\\d{3})+|\\d{4,}/);
                 if (match) {
                     return JSON.stringify({text: text, method: 'id_selector'});
                 }
            }

            // Priority 2: Structure Search (Fallback)
            const containers = document.querySelectorAll('.gold-each-container');
            for (const container of containers) {
                const head = container.querySelector('.gold-bottom .gold-common-head span');
                if (head && head.innerText) {
                    const text = head.innerText.trim();
                    if (text.includes('₹') || text.match(/[\\d,]+/)) {
                         return JSON.stringify({text: text, method: 'structure_fallback'});
                    }
                }
            }
            return null;
        } catch(e) { return null; }
      })();
    """;
  }

  Future<Map<String, dynamic>?> checkAndNotifyGoldPriceChange() async {
    try {
      print('🔄 Background Task: Checking Gold Price...');
      final result = await fetchCurrentGoldPrice();
      final newPrice = result['price'] as GoldPrice?;
      
      if (newPrice != null) {
         // Return data for the background handler to process
         // The background handler (in main.dart or separate file) will:
         // 1. Get previous price from DB
         // 2. Save new price
         // 3. Compare and notify
         return {
           'price': newPrice,
           'method': result['method'],
           'debug': result['debug'],
         };
      }
      return null;
    } catch (e) {
      print('❌ Background Task Error: $e');
      return null;
    }
  }

  /// Fetch gold price with fallback to mock data for testing
  Future<Map<String, dynamic>> fetchGoldPriceWithFallback() async {
    final result = await fetchCurrentGoldPrice();
    final price = result['price'] as GoldPrice?;
    
    if (price != null) {
      return result;
    }
    
    print('⚠️ Using fallback mock data');
    // Fallback to mock data for testing
    return {
      'price': GoldPrice(
        date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
        price22k: 14600.0,
        price24k: 15928.0,
        city: 'Chennai',
      ),
      'method': 'mock_fallback',
      'debug': 'Using mock data as fallback',
    };
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

