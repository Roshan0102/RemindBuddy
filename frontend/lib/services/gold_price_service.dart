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
  /// 1. Try BankBazaar (Primary)
  /// 2. If fails or invalid (< 1000), Try GoodReturns (Secondary) using ID Selector
  /// Fetch current gold price
  /// Returns a map with 'price', 'method', 'debug', and 'log'
  Future<Map<String, dynamic>> fetchCurrentGoldPrice() async {
    final StringBuffer logBuffer = StringBuffer();
    void log(String msg) {
      final time = DateFormat('HH:mm:ss').format(DateTime.now());
      print('$time $msg');
      logBuffer.writeln('$time $msg');
    }

    log('🚀 Starting Gold Price Fetch...');

    // Only works on mobile platforms for now
    if (kIsWeb) {
      log('❌ Web platform not supported');
      return {
        'price': null, 
        'method': 'web_not_supported', 
        'debug': 'Web platform not supported',
        'log': logBuffer.toString()
      };
    }

    // 1. Try BankBazaar
    log('🔍 Attempting Primary Source: BankBazaar');
    log('🔗 URL: $bankBazaarUrl');
    
    final bbResult = await _fetchFromUrl(
      bankBazaarUrl, 
      'BankBazaar',
      _getBankBazaarScript(),
      log
    );
    
    log('📄 BankBazaar Result: ${bbResult['method']}');
    
    if (bbResult['price'] != null) {
      final price = bbResult['price'] as GoldPrice;
      log('💰 BankBazaar returned price: ₹${price.price22k}');
      
      if (price.price22k > 1000) {
         log('✅ BankBazaar price valid (>1000)');
         bbResult['log'] = logBuffer.toString();
         return bbResult;
      } else {
         log('⚠️ BankBazaar price invalid (<1000): ${price.price22k}');
      }
    } else {
      log('❌ BankBazaar failed: ${bbResult['debug']}');
    }
    
    // 2. Try GoodReturns (Fallback)
    log('🔄 Switching to Secondary Source: GoodReturns');
    log('🔗 URL: $goodReturnsUrl');
    
    final grResult = await _fetchFromUrl(
      goodReturnsUrl,
      'GoodReturns', 
      _getGoodReturnsScript(),
      log
    );

    grResult['log'] = logBuffer.toString();
    return grResult;
  }

  Future<Map<String, dynamic>> _fetchFromUrl(
    String url, 
    String sourceName, 
    String jsScript,
    Function(String) log
  ) async {
    final Completer<Map<String, dynamic>> completer = Completer<Map<String, dynamic>>();
    HeadlessInAppWebView? headlessWebView;

    try {
      log('🕸️ Initializing HeadlessWebView for $sourceName...');
      headlessWebView = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          cacheEnabled: false,
          userAgent: 'Mozilla/5.0 (Linux; Android 10; SM-G973F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        ),
        onLoadStop: (controller, loadedUrl) async {
          log('✅ Page loaded: $loadedUrl');
          try {
            log('📜 Executing JS extraction script...');
            final String? priceText = await controller.evaluateJavascript(source: jsScript);
            log('📊 Raw JS Output: $priceText');

            if (priceText != null && priceText.isNotEmpty) {
              await _parseAndComplete(priceText, sourceName, completer, log);
            } else {
              if (!completer.isCompleted) {
                log('❌ JS returned null or empty string');
                completer.complete({
                  'price': null,
                  'method': '${sourceName.toLowerCase()}_failed',
                  'debug': 'No text returned from JS extraction',
                });
              }
            }
          } catch (e) {
            log('💥 JS Error: $e');
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
           log('🛑 Load Error: code=$code, msg=$message');
           if (!completer.isCompleted) {
             completer.complete({
               'price': null,
               'method': '${sourceName.toLowerCase()}_load_error',
               'debug': 'WebView load error: $code - $message',
             });
           }
        },
      );

      log('▶️ Running HeadlessWebView...');
      await headlessWebView.run();
      
      return await completer.future.timeout(const Duration(seconds: 60), onTimeout: () {
        log('⏰ Timeout waiting for $sourceName (60s)');
        return {
          'price': null,
          'method': '${sourceName.toLowerCase()}_timeout',
          'debug': 'Timeout fetching from $sourceName',
        };
      }).whenComplete(() {
        log('🗑️ Disposing WebView for $sourceName');
        headlessWebView?.dispose();
      });
      
    } catch (e) {
      log('💣 Exception in _fetchFromUrl: $e');
      return {
        'price': null,
        'method': '${sourceName.toLowerCase()}_exception',
        'debug': 'Service exception: $e',
      };
    }
  }

  Future<void> _parseAndComplete(
    String priceText, 
    String source, 
    Completer<Map<String, dynamic>> completer,
    Function(String) log
  ) async {
    try {
      String textToParse = priceText;
      String method = 'unknown';

      // Parse JSON if applicable
      try {
         if (priceText.trim().startsWith('{') && priceText.contains('text')) {
             // Basic JSON extraction to ensure we get the text field
             final clean = priceText.replaceAll(RegExp(r'[{}"]'), '');
             final parts = clean.split(',');
             for (var part in parts) {
               if (part.contains('text:')) textToParse = part.split('text:')[1].trim();
               if (part.contains('method:')) method = part.split('method:')[1].trim();
             }
             log('🧩 Parsed JSON: text="$textToParse", method="$method"');
         }
      } catch (e) {
        log('⚠️ JSON parse error (using raw text): $e');
      }

      // Regex to extract price
      // \d{1,3}(?:,\d{3})+ matches 14,560
      // \d{4,} matches 14560
      final priceMatch = RegExp(r'(\d{1,3}(?:,\d{3})+|\d{4,})').firstMatch(textToParse);
      
      if (priceMatch != null) {
        final priceStr = priceMatch.group(0)!.replaceAll(',', '');
        final price22k = double.tryParse(priceStr);
        log('🔢 Extracted number: $price22k');
        
        if (price22k != null && price22k > 1000 && price22k < 100000) {
          log('✅ Price Valid! Completing with success.');
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
           log('❌ Price out of range (<1000 or >100k)');
           if (!completer.isCompleted) completer.complete({'price': null, 'method': 'invalid_range', 'debug': 'Price out of range: $price22k'});
        }
      } else {
         log('❌ Regex match failed on: "$textToParse"');
         if (!completer.isCompleted) completer.complete({'price': null, 'method': 'parse_fail', 'debug': 'Regex failed on: $textToParse'});
      }
    } catch (e) {
      log('💣 Exception in parsing: $e');
      if (!completer.isCompleted) completer.complete({'price': null, 'method': 'parse_exception', 'debug': 'Exception: $e'});
    }
  }

  // Script for BankBazaar: Targeted Class Search with strict validation
  String _getBankBazaarScript() {
    return """
      (function() {
        try {
            // Locate the "Today's Gold Rate" section specifically
            const h2s = document.getElementsByTagName('h2');
            for (let i = 0; i < h2s.length; i++) {
                if (h2s[i].innerText.includes("Today's Gold Rate") || h2s[i].innerText.includes("Rate in Chennai")) {
                    const parent = h2s[i].parentElement;
                    if (parent) {
                        const priceSpan = parent.querySelector('.white-space-nowrap');
                        if (priceSpan) {
                            const text = priceSpan.innerText.trim();
                            
                            // Client-side validation
                            // Check for at least 4 digits to avoid dates like "14"
                            // Regex: 1,000 to 99,999
                            const match = text.match(/(\\d{1,3},\\d{3}|\\d{4,})/);
                            
                            if (match) {
                                const val = parseFloat(match[0].replace(/,/g, ''));
                                if (val > 1000) {
                                    return JSON.stringify({text: text, method: 'bankbazaar_class_match'});
                                }
                            }
                            return JSON.stringify({text: text + " (Invalid value)", method: 'invalid_value_check'}); 
                        }
                    }
                }
            }
            return null;
        } catch(e) { return "JS_EXCEPTION: " + e.toString(); }
      })();
    """;
  }

  // Script for GoodReturns: ID SELECTOR ONLY
  String _getGoodReturnsScript() {
    return """
      (function() {
        try {
            // ID Selector: #22K-price
            const el = document.getElementById('22K-price');
            if (el && el.innerText) {
                 return JSON.stringify({text: el.innerText.trim(), method: 'id_selector'});
            }
            // Debug info if ID not found
            // let debug = "ID 22K-price not found. All IDs: ";
            // const all = document.querySelectorAll('[id*="price"]');
            // for(let i=0; i<all.length; i++) debug += all[i].id + ", ";
            return "ID_NOT_FOUND";
        } catch(e) { return "JS_EXCEPTION: " + e.toString(); }
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

