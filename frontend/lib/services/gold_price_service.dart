import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:intl/intl.dart';
import '../models/gold_price.dart';

class GoldPriceService {
  static final GoldPriceService _instance = GoldPriceService._internal();
  factory GoldPriceService() => _instance;
  GoldPriceService._internal();

  static const String baseUrl = 'https://www.bankbazaar.com/gold-rate-chennai.html';

  /// Fetch current gold price from bankbazaar.com
  /// Uses XPath to extract price from the specific DOM element
  /// Uses HeadlessInAppWebView to bypass Cloudflare protection
  Future<Map<String, dynamic>> fetchCurrentGoldPrice() async {
    // Only works on mobile platforms for now
    if (kIsWeb) return {'price': null, 'method': 'web_not_supported', 'debug': 'Web platform not supported'};

    final Completer<Map<String, dynamic>> completer = Completer<Map<String, dynamic>>();
    
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
            // Use XPath to extract the price directly from the DOM
            // XPath: //*[@id="lp-root"]/div/div[2]/div/div[2]/div/div[3]/div[2]/div[2]/div/div[1]/span[1]/span[1]
            final String? priceText = await controller.evaluateJavascript(source: """
              (function() {
                try {
                  // Method 1: Use XPath to find the exact element (PRIMARY)
                  function getElementByXPath(xpath) {
                    return document.evaluate(xpath, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
                  }
                  
                  const xpath = '//*[@id="lp-root"]/div/div[2]/div/div[2]/div/div[3]/div[2]/div[2]/div/div[1]/span[1]/span[1]';
                  const priceElement = getElementByXPath(xpath);
                  
                  if (priceElement && priceElement.innerText) {
                    console.log('✅ Method 1 (XPath): Success');
                    return JSON.stringify({text: priceElement.innerText.trim(), method: 'xpath'});
                  }
                  
                  // Method 2: Old inspection method - Find price in specific structure (FALLBACK 1)
                  const priceContainers = document.querySelectorAll('[class*="price"], [class*="rate"]');
                  for (let container of priceContainers) {
                    const text = container.innerText || container.textContent;
                    if (text && text.includes('₹') && text.match(/\\d{2,}/)) {
                      console.log('✅ Method 2 (Inspection): Success');
                      return JSON.stringify({text: text.trim(), method: 'inspection'});
                    }
                  }
                  
                  // Method 3: Look for "Today's Gold Rate" heading (FALLBACK 2)
                  const h2Elements = document.getElementsByTagName('h2');
                  for (let i = 0; i < h2Elements.length; i++) {
                    if (h2Elements[i].innerText.includes("Today's Gold Rate") || 
                        h2Elements[i].innerText.includes("Gold Rate")) {
                      const parentDiv = h2Elements[i].parentElement;
                      if (parentDiv) {
                        const priceSpan = parentDiv.querySelector('.white-space-nowrap');
                        if (priceSpan) {
                          console.log('✅ Method 3 (Heading Search): Success');
                          return JSON.stringify({text: priceSpan.innerText.trim(), method: 'heading_search'});
                        }
                      }
                    }
                  }
                  
                  // Method 4: Search for any element with white-space-nowrap containing ₹ (FALLBACK 3)
                  const allSpans = document.querySelectorAll('.white-space-nowrap');
                  for (let span of allSpans) {
                    if (span.innerText.includes('₹')) {
                      console.log('✅ Method 4 (Generic Search): Success');
                      return JSON.stringify({text: span.innerText.trim(), method: 'generic_search'});
                    }
                  }
                  
                  console.error('❌ All methods failed');
                  return null;
                } catch(e) { 
                  console.error('Error extracting price:', e);
                  return null; 
                }
              })();
            """);

            print('📊 Extracted text from WebView: $priceText');

            if (priceText != null && priceText.isNotEmpty) {
              try {
                String textToParse = priceText;
                String method = 'unknown';
                
                // Try to parse as JSON first (new format)
                try {
                  final parsed = priceText.replaceAll("'", '"');
                  if (parsed.contains('{') && parsed.contains('}')) {
                    final jsonStart = parsed.indexOf('{');
                    final jsonEnd = parsed.lastIndexOf('}') + 1;
                    final jsonStr = parsed.substring(jsonStart, jsonEnd);
                    final data = jsonStr.split(',');
                    for (var item in data) {
                      if (item.contains('text')) {
                        textToParse = item.split(':')[1].replaceAll('"', '').replaceAll('}', '').trim();
                      }
                      if (item.contains('method')) {
                        method = item.split(':')[1].replaceAll('"', '').replaceAll('}', '').trim();
                      }
                    }
                  }
                } catch (e) {
                  // Not JSON, use as is
                }
                
                // Extract number from text like "₹ 14,400" or "₹14,400" or "14,400"
                final priceStr = textToParse.replaceAll(RegExp(r'[₹,\s]'), '');
                final price22k = double.tryParse(priceStr);
                
                if (price22k != null && price22k > 1000 && price22k < 100000) {
                  print('💰 Parsed 22K price: ₹$price22k using method: $method');
                  completer.complete({
                    'price': GoldPrice(
                      date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
                      price22k: price22k,
                      price24k: 0.0,
                      city: 'Chennai',
                    ),
                    'method': method,
                    'debug': 'Successfully fetched using $method method',
                  });
                } else {
                  print('⚠️ Parsed price seems invalid: $price22k');
                  completer.complete({
                    'price': null,
                    'method': 'parse_failed',
                    'debug': 'Parsed price invalid: $price22k from text: $textToParse',
                  });
                }
              } catch (e) {
                print('❌ Error parsing price: $e');
                completer.complete({
                  'price': null,
                  'method': 'exception',
                  'debug': 'Exception during parsing: $e',
                });
              }
            } else {
              print('❌ Could not find gold price in WebView DOM');
              completer.complete({
                'price': null,
                'method': 'not_found',
                'debug': 'Could not find gold price in DOM',
              });
            }
          } catch (e) {
            print('❌ Error evaluating JS in WebView: $e');
            completer.complete({
              'price': null,
              'method': 'js_error',
              'debug': 'JS evaluation error: $e',
            });
          }
        },
        onReceivedError: (controller, request, error) {
           print('❌ WebView Error: ${error.description}');
           if (!completer.isCompleted) {
             completer.complete({
               'price': null,
               'method': 'webview_error',
               'debug': 'WebView error: ${error.description}',
             });
           }
        },
        onReceivedHttpError: (controller, request, response) {
           print('❌ WebView HTTP Error: ${response.statusCode}');
        },
      );

      // Run the headless webview
      await headlessWebView.run();
      
      // Set a timeout of 30 seconds
      return await completer.future.timeout(const Duration(seconds: 30), onTimeout: () {
        print('⏳ WebView timed out');
        return {
          'price': null,
          'method': 'timeout',
          'debug': 'WebView request timed out after 30 seconds',
        };
      }).whenComplete(() {
        // Clean up
        headlessWebView?.dispose();
      });

    } catch (e) {
      print('❌ Error in Headless WebView service: $e');
      return {
        'price': null,
        'method': 'exception',
        'debug': 'Service exception: $e',
      };
    }
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

