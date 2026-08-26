import '../models/sms_transaction.dart';

class SmsParserService {
  static final Map<String, String> _knownBanks = {
    'HDFCBK': 'HDFC Bank',
    'SBIBNK': 'SBI',
    'ICICIB': 'ICICI Bank',
    'AXISBK': 'Axis Bank',
    'KOTAKB': 'Kotak Mahindra',
    'PAYTM': 'Paytm Payments Bank',
    'INDUSB': 'IndusInd Bank',
    'CANBNK': 'Canara Bank',
    'BOBTXT': 'Bank of Baroda',
    'UNIONB': 'Union Bank',
    'YESBNK': 'Yes Bank',
    'PNBSMS': 'Punjab National Bank',
    'IDFCFB': 'IDFC FIRST Bank',
    'FEDERAL': 'Federal Bank',
    'BOISMS': 'Bank of India',
  };

  /// Parses a single SMS body and returns an [SmsTransaction] if it's a valid bank transaction, or null otherwise.
  static SmsTransaction? parseSms(String sender, String rawBody, int timestampMillis) {
    if (rawBody.isEmpty) return null;

    // Step A: Strip out common bank security & dispute footers (e.g. "Not You? Call 1800.../SMS BLOCK UPI to 7308080808")
    final String body = _stripDisputeFooters(rawBody);

    final String lowerBody = body.toLowerCase();

    // 1. Check if SMS contains financial transaction keywords
    final bool hasDebitKeyword = lowerBody.contains('debited') ||
        lowerBody.contains('debit') ||
        lowerBody.contains('spent') ||
        lowerBody.contains('paid') ||
        lowerBody.contains('sent') ||
        lowerBody.contains('transferred') ||
        lowerBody.contains('purchase') ||
        lowerBody.contains('withdrawn') ||
        lowerBody.contains('withdrawal') ||
        lowerBody.contains('cash wdl') ||
        lowerBody.contains('atm wdl') ||
        lowerBody.contains('atm') ||
        lowerBody.contains('deducted') ||
        lowerBody.contains('dr ') ||
        lowerBody.contains('dr.');

    final bool hasCreditKeyword = lowerBody.contains('credited') ||
        lowerBody.contains('credit') ||
        lowerBody.contains('received') ||
        lowerBody.contains('deposited') ||
        lowerBody.contains('deposit') ||
        lowerBody.contains('added') ||
        lowerBody.contains('refund') ||
        lowerBody.contains('refunded') ||
        lowerBody.contains('reversed') ||
        lowerBody.contains('reversal') ||
        lowerBody.contains('cashback') ||
        lowerBody.contains('salary') ||
        lowerBody.contains('interest') ||
        lowerBody.contains('dividend') ||
        lowerBody.contains('inward') ||
        lowerBody.contains('transferred from') ||
        lowerBody.contains('received from') ||
        lowerBody.contains('got ') ||
        lowerBody.contains('cr ') ||
        lowerBody.contains('cr.');

    if (!hasDebitKeyword && !hasCreditKeyword) {
      return null; // Not a financial transaction SMS
    }

    // Filter out OTPs / security alerts that lack transaction action verbs
    final bool isOtp = lowerBody.contains('otp') ||
        lowerBody.contains('one time password') ||
        lowerBody.contains('verification code') ||
        lowerBody.contains('secret code');
    final bool hasExplicitTxnVerb = lowerBody.contains('debited') ||
        lowerBody.contains('credited') ||
        lowerBody.contains('spent') ||
        lowerBody.contains('paid') ||
        lowerBody.contains('withdrawn') ||
        lowerBody.contains('refund');

    if (isOtp && !hasExplicitTxnVerb) {
      return null; // Drop non-payment OTP message
    }

    // Determine type: Handle Credit vs Debit priority correctly
    String type = 'Debit';

    final bool isExplicitCreditAction = lowerBody.contains('refund') ||
        lowerBody.contains('refunded') ||
        lowerBody.contains('reversed') ||
        lowerBody.contains('reversal') ||
        lowerBody.contains('cashback') ||
        lowerBody.contains('salary') ||
        lowerBody.contains('interest') ||
        lowerBody.contains('received from') ||
        lowerBody.contains('transferred from') ||
        (lowerBody.contains('credited') && !lowerBody.contains('debited'));

    if (isExplicitCreditAction) {
      type = 'Credit';
    } else if (hasDebitKeyword && (lowerBody.contains('debited') || lowerBody.contains('spent') || lowerBody.contains('paid') || lowerBody.contains('withdrawn') || lowerBody.contains('deducted') || lowerBody.contains('sent'))) {
      type = 'Debit';
    } else if (hasCreditKeyword) {
      type = 'Credit';
    } else {
      type = 'Debit';
    }

    // 2. Extract Bank Name
    final String bankName = _extractBankName(sender, body);

    // 3. Extract Amount
    double amount = 0.0;
    
    // Pattern A: Rs./INR/₹ followed by digits (e.g. "Rs. 450.00", "INR 1,200", "₹50")
    final RegExp amountRegExpA = RegExp(
      r'(?:rs\.?|inr|₹|amt|amount)\s*:?\s*([\d,]+(?:\.\d{1,2})?)',
      caseSensitive: false,
    );

    // Pattern B: debited/credited/spent/paid/sent followed by amount (e.g. "debited by 450.00", "debited 450", "paid 200")
    final RegExp amountRegExpB = RegExp(
      r'(?:debited|credited|spent|paid|sent|withdrawn|deducted|txn|transaction)\s*(?:by|for|of|with|is|was)?\s*:?\s*(?:rs\.?|inr|₹)?\s*([\d,]+(?:\.\d{1,2})?)',
      caseSensitive: false,
    );

    // Pattern C: digits followed by debited/credited (e.g. "450.00 debited")
    final RegExp amountRegExpC = RegExp(
      r'([\d,]+(?:\.\d{1,2})?)\s*(?:debited|credited|spent|paid|deducted)',
      caseSensitive: false,
    );

    var match = amountRegExpA.firstMatch(body);
    if (match != null && match.group(1) != null) {
      final String rawAmt = match.group(1)!.replaceAll(',', '');
      amount = double.tryParse(rawAmt) ?? 0.0;
    }

    if (amount <= 0.0) {
      match = amountRegExpB.firstMatch(body);
      if (match != null && match.group(1) != null) {
        final String rawAmt = match.group(1)!.replaceAll(',', '');
        amount = double.tryParse(rawAmt) ?? 0.0;
      }
    }

    if (amount <= 0.0) {
      match = amountRegExpC.firstMatch(body);
      if (match != null && match.group(1) != null) {
        final String rawAmt = match.group(1)!.replaceAll(',', '');
        amount = double.tryParse(rawAmt) ?? 0.0;
      }
    }

    if (amount <= 0.0) return null; // Could not parse valid positive amount

    // 4. Extract Account / Card Last 4 digits
    String accountLast4 = '';
    final RegExp acctRegExp = RegExp(
      r'(?:a\/c|ac|account|card|acct)\s*(?:no\.?)?\s*(?:ending|s)?\s*[\*xX]*([0-9]{3,4})',
      caseSensitive: false,
    );
    final acctMatch = acctRegExp.firstMatch(body);
    if (acctMatch != null && acctMatch.group(1) != null) {
      accountLast4 = acctMatch.group(1)!;
    }

    // 5. Extract Payee / Merchant / Recipient Name
    final String payee = _extractPayee(body, type);

    final DateTime timestamp = DateTime.fromMillisecondsSinceEpoch(timestampMillis);
    final String id = 'sms_${timestamp.millisecondsSinceEpoch}_${amount.toInt()}';

    return SmsTransaction(
      id: id,
      bankName: bankName,
      accountLast4: accountLast4,
      type: type,
      amount: amount,
      payee: payee,
      timestamp: timestamp,
      isVerified: false,
      category: 'Uncategorized',
      notes: body,
    );
  }

  /// Extracted Bank Name from SMS sender header & body matching top 45+ Indian Banks & Financial Institutions
  static String _extractBankName(String sender, String body) {
    // Extract TRAI 6-character sender ID (e.g. "AD-HDFCBK" -> "HDFCBK", "AX-SBIBNK" -> "SBIBNK")
    String headerCode = sender.toUpperCase().trim();
    if (headerCode.contains('-')) {
      final parts = headerCode.split('-');
      if (parts.length > 1) {
        headerCode = parts.last; // Extracts second part: HDFCBK, SBIBNK, INDNBN, etc.
      }
    }
    final String cleanSender = headerCode.replaceAll(' ', '');
    final String cleanBody = body.toLowerCase();

    final List<_BankMatchRule> bankRules = [
      _BankMatchRule('HDFC Bank', ['HDFCBK', 'HDFC'], ['hdfc bank', 'hdfc']),
      _BankMatchRule('SBI', ['SBIBNK', 'SBIN', 'SBI'], ['state bank of india', 'state bank', 'sbi']),
      _BankMatchRule('ICICI Bank', ['ICICIB', 'ICICI'], ['icici bank', 'icici']),
      _BankMatchRule('Axis Bank', ['AXISBK', 'UTIB', 'AXIS'], ['axis bank', 'axis']),
      _BankMatchRule('Kotak Bank', ['KOTAKB', 'KOTAK'], ['kotak mahindra', 'kotak bank', 'kotak']),
      _BankMatchRule('Indian Bank', ['INDNBN', 'INDIBK', 'INDIANB'], ['indian bank', 'indianb']),
      _BankMatchRule('Bank of Baroda', ['BOBTXT', 'BOB', 'BARODA'], ['bank of baroda', 'baroda bank', 'bob']),
      _BankMatchRule('Canara Bank', ['CANBNK', 'CNRB', 'CANARA'], ['canara bank', 'canara']),
      _BankMatchRule('Union Bank', ['UNIONB', 'UBOI'], ['union bank of india', 'union bank', 'uboi']),
      _BankMatchRule('PNB', ['PNBSMS', 'PNB'], ['punjab national bank', 'pnb']),
      _BankMatchRule('IndusInd Bank', ['INDUSB', 'INDUS'], ['indusind bank', 'indusind']),
      _BankMatchRule('IDFC FIRST Bank', ['IDFCFB', 'IDFC'], ['idfc first bank', 'idfc bank', 'idfc']),
      _BankMatchRule('YES Bank', ['YESBNK', 'YES'], ['yes bank']),
      _BankMatchRule('Bank of India', ['BOISMS', 'BKID', 'BOI'], ['bank of india', 'boi']),
      _BankMatchRule('Central Bank', ['CENTRAL', 'CBI'], ['central bank of india', 'central bank']),
      _BankMatchRule('Indian Overseas Bank', ['IOB'], ['indian overseas bank', 'iob']),
      _BankMatchRule('UCO Bank', ['UCOBNK', 'UCO'], ['uco bank', 'uco']),
      _BankMatchRule('Bank of Maharashtra', ['MAHABK'], ['bank of maharashtra', 'mahabank']),
      _BankMatchRule('Punjab & Sind Bank', ['PSB'], ['punjab & sind', 'punjab and sind']),
      _BankMatchRule('IDBI Bank', ['IBKL', 'IDBI'], ['idbi bank', 'idbi']),
      _BankMatchRule('Federal Bank', ['FEDERAL', 'FDRL'], ['federal bank', 'federal']),
      _BankMatchRule('South Indian Bank', ['SIB'], ['south indian bank', 'sib']),
      _BankMatchRule('RBL Bank', ['RATN', 'RBL'], ['rbl bank', 'rbl']),
      _BankMatchRule('Karur Vysya Bank', ['KVB'], ['karur vysya', 'kvb']),
      _BankMatchRule('City Union Bank', ['CUB'], ['city union bank', 'cub']),
      _BankMatchRule('Bandhan Bank', ['BANDHAN'], ['bandhan bank', 'bandhan']),
      _BankMatchRule('AU Small Finance Bank', ['AUBANK', 'AU'], ['au small finance', 'au bank']),
      _BankMatchRule('Equitas Bank', ['EQUITAS'], ['equitas bank', 'equitas']),
      _BankMatchRule('Ujjivan Bank', ['UJJIVAN'], ['ujjivan bank', 'ujjivan']),
      _BankMatchRule('Paytm Bank', ['PAYTM', 'PYTM'], ['paytm payments bank', 'paytm bank', 'paytm']),
      _BankMatchRule('Airtel Bank', ['AIRTEL'], ['airtel payments bank', 'airtel bank']),
      _BankMatchRule('IPPB', ['IPPB'], ['india post payments', 'ippb', 'post office bank']),
      _BankMatchRule('Jio Bank', ['JIO'], ['jio payments bank', 'jio bank']),
      _BankMatchRule('PhonePe', ['PHONEPE', 'YBL', 'IPL'], ['phonepe']),
      _BankMatchRule('Google Pay', ['GPAY'], ['google pay', 'gpay']),
      _BankMatchRule('Fi Money', ['FI'], ['fi money', 'fi bank']),
      _BankMatchRule('Jupiter Money', ['JUPITER'], ['jupiter money', 'jupiter']),
      _BankMatchRule('Slice', ['SLICE'], ['slice card', 'slice']),
      _BankMatchRule('Uni Card', ['UNI'], ['uni card', 'uni pay']),
      _BankMatchRule('OneCard', ['ONECARD'], ['onecard']),
      _BankMatchRule('Standard Chartered', ['SCB', 'STANCHART'], ['standard chartered', 'stanchart']),
      _BankMatchRule('HSBC', ['HSBC'], ['hsbc bank', 'hsbc']),
      _BankMatchRule('Citibank', ['CITI'], ['citibank', 'citi']),
    ];

    // 1. Check Sender Code Header First
    for (final rule in bankRules) {
      for (final code in rule.senderCodes) {
        if (cleanSender.contains(code)) {
          return rule.bankName;
        }
      }
    }

    // 2. Check Body Text Next
    for (final rule in bankRules) {
      for (final keyword in rule.bodyKeywords) {
        if (cleanBody.contains(keyword)) {
          return rule.bankName;
        }
      }
    }

    // 3. Fallback: Extract 3-4 letter uppercase bank prefix from sender (e.g. AD-DBSBNK -> DBSBNK Bank)
    if (cleanSender.length >= 4) {
      final String code = cleanSender.substring(cleanSender.length - 4);
      return '$code Bank';
    }

    return 'Bank';
  }

  /// Truncates SMS body before common bank dispute & security footers
  static String _stripDisputeFooters(String body) {
    final lower = body.toLowerCase();
    int cutIndex = body.length;

    final List<String> footerTriggers = [
      'not you?',
      'if not done by you',
      'if not you',
      'if not u',
      'call 1800',
      'call 180',
      'call 19',
      'sms block',
      'block upi',
      'block card',
      'report fraud',
      'to report',
      'contact bank',
    ];

    for (final trigger in footerTriggers) {
      final idx = lower.indexOf(trigger);
      if (idx != -1 && idx < cutIndex) {
        cutIndex = idx;
      }
    }

    return body.substring(0, cutIndex).trim();
  }

  /// Extracts Payee / Merchant / Recipient name using multi-pattern matching and candidate validation
  static String _extractPayee(String body, String type) {
    // Step 0: ATM Cash Withdrawal Pattern
    final String lower = body.toLowerCase();
    if (lower.contains('atm') || lower.contains('cash wdl') || lower.contains('cash withdrawal')) {
      final RegExp atmLocationRegExp = RegExp(
        r'\bat\s+([A-Za-z0-9_\-\.\s&]{2,35}?atm[A-Za-z0-9_\-\.\s&]{0,25}?)(?=\s+on|\s+ref|\s+avail|\s+bal|\s+dt|\.|\s*$)',
        caseSensitive: false,
      );
      final atmMatch = atmLocationRegExp.firstMatch(body);
      if (atmMatch != null && atmMatch.group(1) != null) {
        final String candidate = _cleanPayeeCandidate(atmMatch.group(1)!);
        if (candidate.isNotEmpty) return candidate;
      }
      return 'ATM Cash Withdrawal';
    }

    // Step 1: UPI Info format
    final RegExp upiInfoRegExp = RegExp(
      r'(?:upi|ref|info)[\/\s\:\-]*[0-9]*[\/\s]+([A-Za-z0-9_\-\.\s]{2,30}?)(?=\.|\s+on|\s+avail|\s+bal|\s+ref|\s+dt|\s*$)',
      caseSensitive: false,
    );
    for (final m in upiInfoRegExp.allMatches(body)) {
      if (m.group(1) != null) {
        final String candidate = _cleanPayeeCandidate(m.group(1)!);
        if (candidate.isNotEmpty) return candidate;
      }
    }

    // Step 2: VPA Format
    final RegExp vpaRegExp = RegExp(
      r'(?:vpa|to vpa)\s+([a-zA-Z0-9.\-_]+@[a-zA-Z0-9]+|[a-zA-Z0-9.\-_]{3,25})',
      caseSensitive: false,
    );
    for (final m in vpaRegExp.allMatches(body)) {
      if (m.group(1) != null) {
        String rawVpa = m.group(1)!;
        if (rawVpa.contains('@')) {
          rawVpa = rawVpa.split('@').first;
        }
        final String candidate = _cleanPayeeCandidate(rawVpa);
        if (candidate.isNotEmpty) return candidate;
      }
    }

    // Step 3: Card POS / Online Merchant ("at [Merchant]")
    final RegExp atRegExp = RegExp(
      r'\bat\s+([A-Za-z0-9_\-\.\s&]{2,30}?)(?=\s+on|\s+ref|\s+avail|\s+bal|\s+link|\s+dt|\.|\s*$)',
      caseSensitive: false,
    );
    for (final m in atRegExp.allMatches(body)) {
      if (m.group(1) != null) {
        final String candidate = _cleanPayeeCandidate(m.group(1)!);
        if (candidate.isNotEmpty) return candidate;
      }
    }

    // Step 4: "to [Payee]", "paid to [Payee]", "sent to [Payee]", "transferred to [Payee]", "towards [Payee]"
    final RegExp toRegExp = RegExp(
      r'(?:paid to|sent to|transfer to|transferred to|debited to|towards|to)\s+([A-Za-z0-9_\-\.\s&]{2,35}?)(?=\s+using|\s+via|\s+on|\s+ref|\s+avail|\s+bal|\s+upi|\s+a\/c|\.|\(|\)|\n|$)',
      caseSensitive: false,
    );
    for (final m in toRegExp.allMatches(body)) {
      if (m.group(1) != null) {
        final String candidate = _cleanPayeeCandidate(m.group(1)!);
        if (candidate.isNotEmpty) return candidate;
      }
    }

    // Step 5: "received from [Payee]", "from [Payee]", "credited by [Payee]"
    final RegExp fromRegExp = RegExp(
      r'(?:received from|received payment of|credited by|transfer from|from)\s+([A-Za-z0-9_\-\.\s&]{2,35}?)(?=\s+via|\s+on|\s+ref|\s+avail|\s+bal|\s+upi|\s+a\/c|\.|\(|\)|\n|$)',
      caseSensitive: false,
    );
    for (final m in fromRegExp.allMatches(body)) {
      if (m.group(1) != null) {
        final String candidate = _cleanPayeeCandidate(m.group(1)!);
        if (candidate.isNotEmpty) return candidate;
      }
    }

    // Step 6: "by [Payee]", "by transfer to [Payee]", "by IMPS to [Payee]"
    final RegExp byRegExp = RegExp(
      r'(?:by transfer to|by upi|by imps to|by neft to|by)\s+([A-Za-z0-9_\-\.\s&]{2,35}?)(?=\s+ref|\s+on|\s+avail|\s+bal|\.|\(|\)|\n|$)',
      caseSensitive: false,
    );
    for (final m in byRegExp.allMatches(body)) {
      if (m.group(1) != null) {
        final String candidate = _cleanPayeeCandidate(m.group(1)!);
        if (candidate.isNotEmpty) return candidate;
      }
    }

    return 'Unknown Merchant';
  }

  static String _cleanPayeeCandidate(String raw) {
    String clean = raw.trim();
    if (clean.contains('\n')) {
      clean = clean.split('\n').first.trim();
    }
    final lower = clean.toLowerCase();

    // Rejection 1: Reject pure numbers or phone numbers (e.g. "7308080808", "18002586161")
    if (RegExp(r'^\+?\d{8,15}$').hasMatch(clean.replaceAll(RegExp(r'[\s\-]'), ''))) {
      return '';
    }

    // Rejection 2: Dispute & security keywords
    if (lower.contains('block') ||
        lower.contains('upi to') ||
        lower.contains('1800') ||
        lower.contains('report') ||
        lower.contains('fraud') ||
        lower.contains('call') ||
        lower.contains('customer care')) {
      return '';
    }

    // Rejection 3: Generic words
    if (lower == 'account' ||
        lower == 'your' ||
        lower == 'a/c' ||
        lower == 'bank' ||
        lower == 'ref' ||
        lower == 'upi' ||
        lower == 'rs' ||
        lower == 'inr' ||
        lower.startsWith('your a/c') ||
        lower.startsWith('account')) {
      return '';
    }

    clean = clean.replaceAll(RegExp(r'^[^\w]+|[^\w]+$'), '');
    if (clean.length < 2 || clean.length > 35) return '';

    return clean.split(' ').map((word) {
      if (word.isEmpty) return '';
      if (word.length == 1) return word.toUpperCase();
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }
}

class _BankMatchRule {
  final String bankName;
  final List<String> senderCodes;
  final List<String> bodyKeywords;

  const _BankMatchRule(this.bankName, this.senderCodes, this.bodyKeywords);
}
