import '../models/sms_transaction.dart';

class UpiNotificationParserService {
  /// Known Indian UPI app package identifiers mapped to display names
  static const Map<String, String> supportedPackages = {
    'com.google.android.apps.nbu.paisa.user': 'GPay',
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
    'tech.fyle.navi': 'Navi',
    'money.jupiter': 'Jupiter',
    'com.tatadigital.tcp': 'Tata Neu',
    'com.whatsapp': 'WhatsApp Pay',
    'com.whatsapp.w4b': 'WhatsApp Pay',
    'com.freecharge.android': 'Freecharge',
    'com.mobikwik_new': 'MobiKwik',
    'money.fi.banking': 'Fi Money',
    'org.cosmic.slice': 'Slice',
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

    // Ignore promotional, marketing, recharge reminders, loan ads, WhatsApp chats, and OTP notifications
    if (_isIgnoredNotification(lower, packageName)) return null;

    final String displayAppName = appName.isNotEmpty
        ? appName
        : (supportedPackages[packageName] ?? 'UPI App');

    final DateTime timestamp = DateTime.fromMillisecondsSinceEpoch(timestampMillis > 0 ? timestampMillis : DateTime.now().millisecondsSinceEpoch);

    // 1. Determine Credit vs Debit (strictly returns null if no valid transaction verb is found)
    final String? type = _detectTransactionType(lower);
    if (type == null) return null;

    // 2. Extract Amount
    final double? parsedAmount = _extractAmount(combined);
    if (parsedAmount == null || parsedAmount <= 0) return null;

    // 3. Extract Payee / Sender Name
    final String payee = _extractPayeeName(title, body, type, displayAppName);

    // 4. Extract UPI Reference Number / UTR if present
    final String upiRef = _extractUpiReference(combined);

    final double finalAmount = parsedAmount;
    final String txId = 'notif_${timestamp.millisecondsSinceEpoch}_${finalAmount.toInt()}';

    return SmsTransaction(
      id: txId,
      sender: displayAppName,
      bankName: displayAppName,
      accountLast4: 'UPI',
      type: type,
      amount: finalAmount,
      payee: payee.isNotEmpty ? payee : 'Unknown Payee',
      timestamp: timestamp,
      isVerified: false,
      category: 'Untagged',
      notes: body.isNotEmpty ? body : title,
      source: 'notification',
      sourceApp: displayAppName,
      upiRef: upiRef,
      rawTitle: title,
      rawBody: body,
    );
  }

  static bool _isIgnoredNotification(String lower, String packageName) {
    // If notification is from WhatsApp, strictly require real WhatsApp Pay transaction phrases
    if (packageName.contains('whatsapp')) {
      final bool isWhatsAppPayment = lower.contains('paid you') ||
          lower.contains('sent you') ||
          lower.contains('you paid') ||
          lower.contains('you sent') ||
          lower.contains('payment received') ||
          lower.contains('payment of') ||
          lower.contains('payment completed') ||
          lower.contains('payment successful') ||
          lower.contains('transferred to your');
      if (!isWhatsAppPayment) return true;
    }

    const ignoredKeywords = [
      'ready for use',
      'get up to',
      'win up to',
      'earn up to',
      'stand a chance',
      't&c apply',
      't&c',
      'terms & conditions',
      'terms and conditions',
      'on next transaction',
      'on your next',
      'cashback on',
      'cashback offer',
      'flat cashback',
      'clean bank statements',
      'pin-payments',
      'fast pin',
      'cashback won',
      'spin to win',
      'spin and win',
      'scratch card',
      'loan approved',
      'instant loan',
      'pre-approved',
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
      'promo code',
      'apply coupon',
      'voucher',
      'special offer',
      'check balance',
      'balance goes above',
      'balance goes below',
      'threshold limit',
      'daily balance alert',
      'balance alert',
      'low balance alert',
      'present balance of',
    ];

    for (final kw in ignoredKeywords) {
      if (lower.contains(kw)) {
        final bool hasExplicitTxn = lower.contains('debited') ||
            lower.contains('credited') ||
            lower.contains('you paid') ||
            lower.contains('paid to') ||
            lower.contains('sent to') ||
            lower.contains('paid you') ||
            lower.contains('sent you') ||
            lower.contains('withdrawn') ||
            lower.contains('spent');
        if (!hasExplicitTxn) return true;
      }
    }
    return false;
  }

  static String? _detectTransactionType(String lower) {
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
    return null; // Return null if no transaction verb is present
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

    // Patterns for Credit: "Rahul Sharma paid you ₹500", "Received ₹500 from Priya Patel", "Alex sent you ₹200", "Rahul has sent you ₹50"
    if (type == 'Credit') {
      final p1Body = RegExp(r'^(.*?)\s+(?:has\s+)?(?:paid|sent)\s+you', caseSensitive: false).firstMatch(body);
      if (p1Body != null && p1Body.group(1)!.trim().isNotEmpty) {
        return _cleanName(p1Body.group(1)!);
      }

      final p1Title = RegExp(r'^(.*?)\s+(?:has\s+)?(?:paid|sent)\s+you', caseSensitive: false).firstMatch(title);
      if (p1Title != null && p1Title.group(1)!.trim().isNotEmpty) {
        return _cleanName(p1Title.group(1)!);
      }

      final p2 = RegExp(r'from\s+([A-Za-z0-9\s]{2,40}?)(?:\.|\,|\s+(?:via|using|in|for|on|with|upi|ref)|$)', caseSensitive: false).firstMatch(fullText);
      if (p2 != null && p2.group(1)!.trim().isNotEmpty) {
        return _cleanName(p2.group(1)!);
      }

      final p3 = RegExp(r'(?:^|[\.\,\;\n\r])\s*(.*?)\s+(?:has\s+)?sent\s+you', caseSensitive: false).firstMatch(fullText);
      if (p3 != null && p3.group(1)!.trim().isNotEmpty) {
        return _cleanName(p3.group(1)!);
      }
    }

    // Patterns for Debit: "You paid ₹500 to Swiggy", "Paid ₹120 to Chai Point", "Payment of ₹450 to Uber"
    if (type == 'Debit') {
      final p1 = RegExp(r'to\s+([A-Za-z0-9\s]{2,40}?)(?:\.|\,|\s+(?:was|is|using|via|on|for|with|upi)|$)', caseSensitive: false).firstMatch(fullText);
      if (p1 != null && p1.group(1)!.trim().isNotEmpty) {
        return _cleanName(p1.group(1)!);
      }

      final p2 = RegExp(r'at\s+([A-Za-z0-9\s]{2,40}?)(?:\.|\,|\s+(?:was|is|using|via|\.|$)|$)', caseSensitive: false).firstMatch(fullText);
      if (p2 != null && p2.group(1)!.trim().isNotEmpty) {
        return _cleanName(p2.group(1)!);
      }
    }

    // Fallback to title if title is a person's name or merchant
    if (title.isNotEmpty &&
        !title.toLowerCase().contains('payment') &&
        !title.toLowerCase().contains('money') &&
        !title.toLowerCase().contains(appName.toLowerCase())) {
      return _cleanName(title);
    }

    return type == 'Credit' ? 'UPI Income' : 'UPI Expense';
  }

  static String _cleanName(String raw) {
    var clean = raw.trim();
    // Remove unwanted leading/trailing words
    clean = clean.replaceAll(RegExp(r'^(payment of|payment to|paid to|money sent to|sent to|received from|from|to)\s+', caseSensitive: false), '');
    clean = clean.replaceAll(RegExp(r'\s+(was successful|successful|completed|successful\.?)$', caseSensitive: false), '');
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
