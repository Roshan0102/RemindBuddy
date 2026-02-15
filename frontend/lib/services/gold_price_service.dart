import 'dart:async';
import 'dart:convert';
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
          log('✅ Page loaded (onLoadStop): $loadedUrl');
          if (!completer.isCompleted) {
             await _extractData(controller, jsScript, sourceName, completer, log);
          }
        },
        onProgressChanged: (controller, progress) async {
           // log('⏳ Loading $sourceName: $progress%'); // Verbose logging
           if (progress == 100) {
              log('💯 Page reached 100% loading');
              // Try extracting if not already done, just in case onLoadStop is delayed
              if (!completer.isCompleted) {
                 log('⚡ Attempting extraction at 100% progress (fallback for onLoadStop)');
                 // Give a small delay for scripts to hydrate
                 await Future.delayed(const Duration(milliseconds: 500));
                 if (!completer.isCompleted) {
                    await _extractData(controller, jsScript, sourceName, completer, log);
                 }
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

  Future<void> _extractData(
      InAppWebViewController controller,
      String jsScript,
      String sourceName,
      Completer<Map<String, dynamic>> completer,
      Function(String) log
  ) async {
      try {
        log('📜 Executing JS extraction script...');
        final String? priceText = await controller.evaluateJavascript(source: jsScript);
        log('📊 Raw JS Output: $priceText');

        if (priceText != null && priceText.isNotEmpty) {
          await _parseAndComplete(priceText, sourceName, completer, log);
        } else {
          // Don't fail immediately on empty return if we are invoked from onProgressChanged, 
          // but if we are here, we usually want to result.
          // Yet, let's only complete if we are sure it failed? 
          // Actually, if JS returns null, it failed to find valid data.
          log('❌ JS returned null or empty string');
          // We don't complete here if called from onProgressChanged because maybe onLoadStop will yield better results?
          // BUT, if we do complete with failure, we stop trying.
          // Let's only complete if we have a success, OR if this is onLoadStop.
          // However, to keep it simple: if extraction fails, we might as well wait for timeout or try again?
          // No, if the script runs and returns null, it likely didn't find the element.
          // Let's complete only if success, or let the timeout handle the failure?
          // NO, we should fail fast if possible.
          // But since we call this from onProgressChanged (early), failing here might be premature.
          // So let's ONLY complete if successful (priceText has data), or if this logic is robust.
          // Actually, let's complete failure only if we are sure.
          // To update: The original code completed on failure.
          // New logic: Only complete if we found something or if we are explicitly in a "must complete" state?
          // Let's stick to completing if result is found, otherwise LOG and wait (unless it's onLoadStop, but even then, maybe wait for timeout?).
          // Actually, if onLoadStop happens and we find nothing, we probably won't find anything later.
          // So I should pass a "forceFailure" flag?
          // Let's just modify _parseAndComplete to handle the logic.
          // For now, if priceText is null, we do NOTHING and let the timeout occur?
          // Or we can complete with failure if we are sure?
          // Let's rely on the timeout for "loading issues", but if the script explicitly returns "ID_NOT_FOUND", we can fail fast.
          if (priceText != null && (priceText.contains("ID_NOT_FOUND") || priceText.contains("JS_EXCEPTION"))) {
             if (!completer.isCompleted) {
                completer.complete({
                  'price': null,
                  'method': '${sourceName.toLowerCase()}_failed',
                  'debug': 'JS returned failure: $priceText',
                });
             }
          }
        }
      } catch (e) {
        log('💥 JS Error during extraction: $e');
        // Don't fail, maybe just a glitch?
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
             final Map<String, dynamic> jsonArgs = jsonDecode(priceText);
             if (jsonArgs.containsKey('text')) {
                textToParse = jsonArgs['text'].toString();
             }
             if (jsonArgs.containsKey('method')) {
                method = jsonArgs['method'].toString();
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
            if (el && el.innerText) {
                 return JSON.stringify({text: el.innerText.trim(), method: 'id_selector'});
            }
            // Fallback: Query Selector for common classes if ID fails (sometimes IDs dynamic?)
            // But user said "check entire good return code", and ID 22K-price is standard.
            // Let's just check standard 22K-price again or return specific error.
            
            // Try querySelector just in case
            const el2 = document.querySelector('#22K-price');
            if (el2 && el2.innerText) return JSON.stringify({text: el2.innerText.trim(), method: 'id_selector_query'});

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

