import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sms_transaction.dart';
import 'upi_notification_parser_service.dart';
import 'log_service.dart';
import 'home_widget_service.dart';

class PaymentNotificationTrackerService {
  static final PaymentNotificationTrackerService _instance = PaymentNotificationTrackerService._internal();
  factory PaymentNotificationTrackerService() => _instance;
  PaymentNotificationTrackerService._internal();

  static const EventChannel _eventChannel = EventChannel('com.remindbuddy/payment_notification_stream');
  static const MethodChannel _methodChannel = MethodChannel('com.remindbuddy/notification_listener');

  StreamSubscription? _streamSubscription;
  bool _isInitialized = false;

  /// Top Supported Indian UPI Apps with package names & display labels
  static const List<Map<String, String>> supportedUpiApps = [
    {'id': 'com.google.android.apps.nbu.paisa.user', 'name': 'Google Pay (GPay)', 'icon': 'gpay'},
    {'id': 'com.google.android.apps.npx', 'name': 'Google Pay (Legacy)', 'icon': 'gpay'},
    {'id': 'com.phonepe.app', 'name': 'PhonePe', 'icon': 'phonepe'},
    {'id': 'net.one97.paytm', 'name': 'Paytm', 'icon': 'paytm'},
    {'id': 'com.dreamplug.androidapp', 'name': 'CRED UPI & Pay', 'icon': 'cred'},
    {'id': 'in.super.money', 'name': 'Super.money (Flipkart)', 'icon': 'supermoney'},
    {'id': 'in.org.npci.upiapp', 'name': 'BHIM (NPCI)', 'icon': 'bhim'},
    {'id': 'in.amazon.mShop.android.shopping', 'name': 'Amazon Pay', 'icon': 'amazon'},
    {'id': 'com.naviapp', 'name': 'Navi UPI', 'icon': 'navi'},
    {'id': 'money.jupiter', 'name': 'Jupiter Money', 'icon': 'jupiter'},
    {'id': 'com.tatadigital.tcp', 'name': 'Tata Neu UPI', 'icon': 'tataneu'},
    {'id': 'com.whatsapp', 'name': 'WhatsApp Pay', 'icon': 'whatsapp'},
    {'id': 'money.fi.banking', 'name': 'Fi Money', 'icon': 'fi'},
    {'id': 'org.cosmic.slice', 'name': 'Slice', 'icon': 'slice'},
    {'id': 'com.myairtelapp', 'name': 'Airtel Pay', 'icon': 'airtel'},
    {'id': 'com.samsung.android.spay', 'name': 'Samsung Wallet', 'icon': 'samsung'},
    {'id': 'com.jio.myjio', 'name': 'JioPay', 'icon': 'jio'},
  ];

  /// Initialize the Payment Notification Tracker service
  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    if (kIsWeb) return;

    try {
      // 1. Flush any pending notifications buffered while app was terminated
      await flushBackgroundBuffer();

      // 2. Start live EventChannel stream
      _streamSubscription = _eventChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          if (event is Map) {
            final map = Map<String, dynamic>.from(event);
            _handleIncomingNotificationMap(map);
          }
        },
        onError: (dynamic error) {
          LogService().error('PaymentNotificationTracker Stream Error', error);
        },
      );
    } catch (e) {
      LogService().error('PaymentNotificationTracker init failed', e);
    }
  }

  /// Check if Android Notification Access permission is granted
  Future<bool> isNotificationAccessGranted() async {
    if (kIsWeb) return false;
    try {
      final bool? granted = await _methodChannel.invokeMethod<bool>('isNotificationAccessGranted');
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Launch Android Notification Access Settings screen
  Future<void> openNotificationAccessSettings() async {
    if (kIsWeb) return;
    try {
      await _methodChannel.invokeMethod('openNotificationAccessSettings');
    } catch (e) {
      LogService().error('Failed to open notification settings', e);
    }
  }

  /// Check if notification tracking is enabled by the user in settings
  Future<bool> isTrackingEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('upi_notification_tracking_enabled') ?? true;
  }

  /// Toggle notification tracking master switch
  Future<void> setTrackingEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('upi_notification_tracking_enabled', enabled);
  }

  /// Get list of enabled UPI app package IDs
  Future<List<String>> getEnabledUpiPackages() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('enabled_upi_packages');
    if (list == null || list.isEmpty) {
      // Default: all supported packages enabled
      return supportedUpiApps.map((a) => a['id']!).toList();
    }
    return list;
  }

  /// Save list of enabled UPI app package IDs
  Future<void> setEnabledUpiPackages(List<String> packages) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('enabled_upi_packages', packages);
  }

  /// Get primary bank mappings for UPI apps (e.g. {'com.google.android.apps.nbu.paisa.user': 'Union Bank'})
  Future<Map<String, String>> getUpiBankMappings() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('upi_bank_map_')).toList();
    final Map<String, String> map = {};
    for (final k in keys) {
      final appId = k.replaceFirst('upi_bank_map_', '');
      final bank = prefs.getString(k);
      if (bank != null && bank.isNotEmpty) {
        map[appId] = bank;
      }
    }
    return map;
  }

  /// Set primary bank mapping for a UPI app
  Future<void> setUpiBankMapping(String appId, String? bankName) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'upi_bank_map_$appId';
    if (bankName == null || bankName.isEmpty || bankName == 'Default' || bankName == 'None') {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, bankName);
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final mappings = await getUpiBankMappings();
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('finance_settings')
            .doc('upi_mappings')
            .set({'mappings': mappings}, SetOptions(merge: true));
      } catch (e) {
        LogService().error('Failed to sync UPI bank mappings to Firestore', e);
      }
    }
  }

  /// Flushes notifications saved by native service while the app was closed
  Future<void> flushBackgroundBuffer() async {
    if (kIsWeb) return;
    try {
      final List<dynamic>? list = await _methodChannel.invokeListMethod('getAndClearPendingNotifications');
      if (list != null && list.isNotEmpty) {
        for (final item in list) {
          if (item is Map) {
            final map = Map<String, dynamic>.from(item);
            await _handleIncomingNotificationMap(map);
          }
        }
      }
    } catch (e) {
      LogService().error('Error flushing notification buffer', e);
    }
  }

  /// Processes a single notification map and triggers the 5-Stage Deduplication Engine
  Future<void> _handleIncomingNotificationMap(Map<String, dynamic> map) async {
    final bool isEnabled = await isTrackingEnabled();
    if (!isEnabled) return;

    final String packageName = map['packageName']?.toString() ?? '';
    final enabledPackages = await getEnabledUpiPackages();
    bool isPackageAllowed = enabledPackages.contains(packageName) || enabledPackages.contains('all');
    if (!isPackageAllowed && (packageName.contains('nbu.paisa') || packageName.contains('npx') || packageName.contains('walletnfcrel'))) {
      isPackageAllowed = enabledPackages.any((p) => p.contains('nbu.paisa') || p.contains('npx') || p.contains('walletnfcrel'));
    }
    if (!isPackageAllowed) {
      return; // App is unselected by user
    }

    final String appName = map['appName']?.toString() ?? '';
    final String title = map['title']?.toString() ?? '';
    final String body = (map['fullBody'] ?? map['body'] ?? map['text'] ?? '').toString();
    final int timestamp = (map['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;

    var parsedTx = UpiNotificationParserService.parseNotification(
      packageName: packageName,
      appName: appName,
      title: title,
      body: body,
      timestampMillis: timestamp,
    );

    if (parsedTx != null) {
      final mappings = await getUpiBankMappings();
      final mappedBank = mappings[packageName] ?? mappings[parsedTx.sourceApp];
      if (mappedBank != null && mappedBank.isNotEmpty && mappedBank != 'Default' && mappedBank != 'None') {
        parsedTx = parsedTx.copyWith(
          bankName: mappedBank,
          sourceApp: '${parsedTx.sourceApp} ($mappedBank)',
        );
      }
      await processAndReconcileTransaction(parsedTx);
    }
  }

  /// 5-Stage Smart Deduplication & Ingestion Engine
  Future<void> processAndReconcileTransaction(SmsTransaction newTx) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final txColl = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('sms_transactions');

      // 1. Fetch recent transactions from the last 15 minutes to check for duplicate/SMS pairing
      final fifteenMinutesAgo = newTx.timestamp.subtract(const Duration(minutes: 15));
      final recentSnap = await txColl
          .where('timestamp', isGreaterThanOrEqualTo: fifteenMinutesAgo.toIso8601String())
          .get();

      SmsTransaction? bestMatch;
      String? bestMatchDocId;
      int highestScore = 0;

      for (var doc in recentSnap.docs) {
        final data = doc.data();
        final existing = SmsTransaction.fromMap(data);

        // Cannot pair with already dual-verified transaction
        if (existing.source == 'both') continue;
        // Cannot pair two notifications with each other or two SMS with each other
        if (existing.source == newTx.source) continue;

        int score = _calculateMatchScore(existing, newTx);
        if (score >= 60 && score > highestScore) {
          highestScore = score;
          bestMatch = existing;
          bestMatchDocId = doc.id;
        }
      }

      if (bestMatch != null && bestMatchDocId != null) {
        // MATCH FOUND: Reconcile and merge into a single verified record
        final String combinedSourceApp = bestMatch.source == 'sms'
            ? '${bestMatch.bankName} + ${newTx.sourceApp}'
            : '${newTx.bankName} + ${bestMatch.sourceApp}';

        // Prefer the clean human payee name from the notification over SMS
        final String cleanPayee = (newTx.source == 'notification' && newTx.payee != 'UPI Transfer' && newTx.payee != 'UPI Income')
            ? newTx.payee
            : (bestMatch.payee != 'UPI Transfer' && bestMatch.payee != 'UPI Income' ? bestMatch.payee : newTx.payee);

        final mergedTx = bestMatch.copyWith(
          source: 'both',
          sourceApp: combinedSourceApp,
          payee: cleanPayee,
          isVerified: true,
          upiRef: bestMatch.upiRef.isNotEmpty ? bestMatch.upiRef : newTx.upiRef,
          notes: '${bestMatch.notes}\n[App Notification: ${newTx.rawBody}]'.trim(),
        );

        await txColl.doc(bestMatchDocId).set(mergedTx.toMap(), SetOptions(merge: true));
        debugPrint("⚡ Reconciled & Paired Transaction: $bestMatchDocId (${mergedTx.payee} - ₹${mergedTx.amount})");
      } else {
        // NO MATCH FOUND: Save as a standalone transaction
        await txColl.doc(newTx.id).set(newTx.toMap(), SetOptions(merge: true));
        debugPrint("💾 Saved New Notification Transaction: ${newTx.id} (${newTx.payee} - ₹${newTx.amount})");
      }
      HomeWidgetService().syncAllWidgets();
    } catch (e) {
      LogService().error('Error reconciling transaction', e);
    }
  }

  /// Calculates similarity score between existing transaction and new transaction
  int _calculateMatchScore(SmsTransaction existing, SmsTransaction newTx) {
    // 1. Amount and Type MUST match exactly
    if (existing.amount != newTx.amount || existing.type != newTx.type) {
      return 0;
    }

    int score = 40; // Base points for exact amount and type match

    // 2. 12-Digit UTR/RRN Match (Deterministic Match)
    if (existing.upiRef.isNotEmpty && newTx.upiRef.isNotEmpty && existing.upiRef == newTx.upiRef) {
      return 100;
    }

    // 3. Time Proximity (Max 5 minutes)
    final diffSeconds = existing.timestamp.difference(newTx.timestamp).inSeconds.abs();
    if (diffSeconds <= 90) {
      score += 35; // Within 1.5 minutes
    } else if (diffSeconds <= 300) {
      score += 20; // Within 5 minutes
    } else {
      return 0; // Too far apart in time
    }

    // 4. Payee Name / Token Overlap
    if (existing.payee.isNotEmpty && newTx.payee.isNotEmpty) {
      final p1 = existing.payee.toLowerCase();
      final p2 = newTx.payee.toLowerCase();
      if (p1 == p2) {
        score += 25;
      } else {
        final words1 = p1.split(RegExp(r'\s+')).where((w) => w.length > 2);
        for (final w in words1) {
          if (p2.contains(w)) {
            score += 15;
            break;
          }
        }
      }
    }

    return score;
  }

  void dispose() {
    _streamSubscription?.cancel();
  }
}
