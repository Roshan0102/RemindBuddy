import '../models/sms_transaction.dart';

class UpiNotificationParserService {
  /// Known Indian UPI app package identifiers mapped to display names
  static const Map<String, String> supportedPackages = {
    'com.google.android.apps.npx': 'GPay',
    'com.google.android.apps.walletnfcrel': 'GPay',
    'com.phonepe.app': 'PhonePe',
    'net.one97.paytm': 'Paytm',
    'com.dreamplug.androidapp': 'CRED',
    'in.super.money': 'Super.money',
    'in.org.npci.upiapp': 'BHIM',
    'in.amazon.mShop.android.shopping': 'Amazon Pay',
    'com.amazon.mShop.android.shopping': 'Amazon Pay',
    'com.naviapp': 'Navi',
    'money.jupiter': 'Jupiter',
    'com.tatadigital.tcp': 'Tata Neu',
    'com.freecharge.android': 'Freecharge',
    'com.mobikwik_new': 'MobiKwik',
  };

  /// Parses an incoming Android status bar notification payload into a verified [SmsTransaction]
  static SmsTransaction? parseNotification({
    required String packageName,
    required String appName,
    required String title,
    required String body,
    required int timestampMillis,
  }) {
    final String combined = '$title $body'.trim();
    if (combined.isEmpty) return null;

    final lower = combined.toLowerCase();

    // Ignore promotional, marketing, recharge reminders, loan ads, and OTP notifications
    if (_isIgnoredNotification(lower)) return null;

    final String displayAppName = appName.isNotEmpty
        ? appName
        : (supportedPackages[packageName] ?? 'UPI App');

    final DateTime timestamp = DateTime.fromMillisecondsSinceEpoch(timestampMillis > 0 ? timestampMillis : DateTime.now().millisecondsSinceEpoch);

    // 1. Determine Credit vs Debit
    final String type = _detectTransactionType(lower);

    // 2. Extract Amount
    final double? parsedAmount = _extractAmount(combined);

    // 3. Extract Payee / Sender Name
    final String payee = _extractPayeeName(title, body, type, displayAppName);

    // 4. Extract UPI Reference Number / UTR if present
    final String upiRef = _extractUpiReference(combined);

    final double finalAmount = parsedAmount ?? 0.0;
    final String txId = 'notif_${timestamp.millisecondsSinceEpoch}_${finalAmount.toInt()}';

    return SmsTransaction(
      id: txId,
      sender: displayAppName,
      bankName: displayAppName,
      accountLast4: 'UPI',
      type: type,
      amount: finalAmount,
      payee: payee.isNotEmpty ? payee : 'UPI Transfer',
      timestamp: timestamp,
      isVerified: finalAmount > 0,
      category: finalAmount > 0 ? 'UPI Transfer' : 'Action Needed',
      notes: body.isNotEmpty ? body : title,
      source: 'notification',
      sourceApp: displayAppName,
      upiRef: upiRef,
      rawTitle: title,
      rawBody: body,
    );
  }

  static bool _isIgnoredNotification(String lower) {
    const ignoredKeywords = [
      'cashback won',
      'spin to win',
      'scratch card',
      'loan approved',
      'instant loan',
      'credit card offer',
      'recharge now',
      'bill due',
      'remind to pay',
      'otp',
      'verification code',
      'flat off',
      'discount',
      'claim now',
      'reward points',
      'check balance',
    ];
    for (final kw in ignoredKeywords) {
      if (lower.contains(kw)) return true;
    }
    return false;
  }

  static String _detectTransactionType(String lower) {
    final creditKeywords = [
      'received',
      'paid you',
      'sent you',
      'credited',
      'added to',
      'incoming',
      'received from',
      'transferred to your',
      'deposited',
    ];

    final debitKeywords = [
      'you paid',
      'paid to',
      'sent to',
      'debited',
      'spent',
      'payment of',
      'successful at',
      'transferred to',
    ];

    for (final kw in creditKeywords) {
      if (lower.contains(kw)) return 'Credit';
    }
    for (final kw in debitKeywords) {
      if (lower.contains(kw)) return 'Debit';
    }
    return 'Debit';
  }

  static double? _extractAmount(String text) {
    // Matches formats: ₹500, ₹ 1,250.50, Rs. 500, Rs 500.00, INR 500
    final RegExp reg = RegExp(
      r'(?:₹|Rs\.?|INR)\s*([\d,]+(?:\.\d{1,2})?)',
      caseSensitive: false,
    );
    final match = reg.firstMatch(text);
    if (match != null) {
      final clean = match.group(1)!.replaceAll(',', '');
      return double.tryParse(clean);
    }

    // Fallback: search for numbers followed by "paid" or "received"
    final RegExp numReg = RegExp(
      r'([\d,]+(?:\.\d{1,2})?)\s*(?:rupees|rs|inr)',
      caseSensitive: false,
    );
    final numMatch = numReg.firstMatch(text);
    if (numMatch != null) {
      final clean = numMatch.group(1)!.replaceAll(',', '');
      return double.tryParse(clean);
    }

    return null;
  }

  static String _extractPayeeName(String title, String body, String type, String appName) {
    final fullText = '$title. $body';

    // Patterns for Credit: "Rahul Sharma paid you ₹500", "Received ₹500 from Priya Patel", "Alex sent you ₹200"
    if (type == 'Credit') {
      final p1 = RegExp(r'^(.*?)\s+paid you', caseSensitive: false).firstMatch(body);
      if (p1 != null && p1.group(1)!.trim().isNotEmpty) {
        return _cleanName(p1.group(1)!);
      }

      final p2 = RegExp(r'from\s+([A-Za-z0-9\s]{2,40}?)(?:\.|\,|\s+(?:via|using|in|for|on|with|upi|ref)|$)', caseSensitive: false).firstMatch(fullText);
      if (p2 != null && p2.group(1)!.trim().isNotEmpty) {
        return _cleanName(p2.group(1)!);
      }

      final p3 = RegExp(r'^(.*?)\s+sent you', caseSensitive: false).firstMatch(body);
      if (p3 != null && p3.group(1)!.trim().isNotEmpty) {
        return _cleanName(p3.group(1)!);
      }
    }

    // Patterns for Debit: "You paid ₹500 to Swiggy", "Paid ₹120 to Chai Point", "Payment of ₹450 to Uber"
    if (type == 'Debit') {
      final p1 = RegExp(r'to\s+([A-Za-z0-9\s]{2,40}?)(?:\.|\,|\s+(?:was|is|using|via|on|for|with|upi)|$)', caseSensitive: false).firstMatch(body);
      if (p1 != null && p1.group(1)!.trim().isNotEmpty) {
        return _cleanName(p1.group(1)!);
      }

      final p2 = RegExp(r'at\s+([A-Za-z0-9\s]{2,40}?)(?:\.|\,|\s+(?:was|is|using|via|\.|$)|$)', caseSensitive: false).firstMatch(body);
      if (p2 != null && p2.group(1)!.trim().isNotEmpty) {
        return _cleanName(p2.group(1)!);
      }
    }

    // Fallback to title if title is a person's name or merchant
    if (title.isNotEmpty && !title.toLowerCase().contains('payment') && !title.toLowerCase().contains('money') && !title.toLowerCase().contains(appName.toLowerCase())) {
      return _cleanName(title);
    }

    return type == 'Credit' ? 'UPI Income' : 'UPI Expense';
  }

  static String _cleanName(String raw) {
    var clean = raw.trim();
    // Remove unwanted leading/trailing words
    clean = clean.replaceAll(RegExp(r'^(payment of|payment to|paid to|money sent to|sent to|received from|from|to)\s+', caseSensitive: false), '');
    clean = clean.replaceAll(RegExp(r'\s+(was successful|successful|completed|successful\.?)$', caseSensitive: false), '');
    // Capitalize words nicely
    if (clean.length > 25) {
      clean = clean.substring(0, 25).trim();
    }
    return clean.trim();
  }

  static String _extractUpiReference(String text) {
    // 12-digit UTR/RRN number
    final RegExp reg = RegExp(r'(?:UPI|Ref|UTR|RRN)\s*(?:No\.?|ID)?\s*[:/]?\s*(\d{12})', caseSensitive: false);
    final match = reg.firstMatch(text);
    if (match != null) {
      return match.group(1)!;
    }
    return '';
  }
}
