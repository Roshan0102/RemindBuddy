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
  };

  /// Parses a single SMS body and returns an [SmsTransaction] if it's a valid bank transaction, or null otherwise.
  static SmsTransaction? parseSms(String sender, String body, int timestampMillis) {
    if (body.isEmpty) return null;

    final String lowerBody = body.toLowerCase();

    // Check if SMS contains financial keywords
    final bool isDebit = lowerBody.contains('debited') ||
        lowerBody.contains('spent') ||
        lowerBody.contains('paid to') ||
        lowerBody.contains('transferred to') ||
        lowerBody.contains('purchase of') ||
        lowerBody.contains('dr ');

    final bool isCredit = lowerBody.contains('credited') ||
        lowerBody.contains('received from') ||
        lowerBody.contains('deposited') ||
        lowerBody.contains('cr ');

    if (!isDebit && !isCredit) {
      return null; // Not a transaction SMS
    }

    final String type = isDebit ? 'Debit' : 'Credit';

    // 1. Extract Bank Name
    String bankName = 'Bank';
    final String cleanSender = sender.toUpperCase().replaceAll('-', '').replaceAll(' ', '');

    for (final entry in _knownBanks.entries) {
      if (cleanSender.contains(entry.key) || body.toUpperCase().contains(entry.value.toUpperCase())) {
        bankName = entry.value;
        break;
      }
    }
    if (bankName == 'Bank') {
      if (lowerBody.contains('hdfc')) bankName = 'HDFC Bank';
      else if (lowerBody.contains('sbi')) bankName = 'SBI';
      else if (lowerBody.contains('icici')) bankName = 'ICICI Bank';
      else if (lowerBody.contains('axis')) bankName = 'Axis Bank';
      else if (lowerBody.contains('kotak')) bankName = 'Kotak Bank';
      else if (lowerBody.contains('paytm')) bankName = 'Paytm Bank';
    }

    // 2. Extract Amount
    double amount = 0.0;
    final RegExp amountRegExp = RegExp(
      r'(?:rs\.?|inr|₹)\s*([\d,]+(?:\.\d{1,2})?)',
      caseSensitive: false,
    );
    final RegExp fallbackAmountRegExp = RegExp(
      r'(?:debited|credited|spent|paid)\s*(?:by|for|of)?\s*(?:rs\.?|inr|₹)?\s*([\d,]+(?:\.\d{1,2})?)',
      caseSensitive: false,
    );

    var match = amountRegExp.firstMatch(body);
    if (match != null && match.group(1) != null) {
      final String rawAmt = match.group(1)!.replaceAll(',', '');
      amount = double.tryParse(rawAmt) ?? 0.0;
    } else {
      match = fallbackAmountRegExp.firstMatch(body);
      if (match != null && match.group(1) != null) {
        final String rawAmt = match.group(1)!.replaceAll(',', '');
        amount = double.tryParse(rawAmt) ?? 0.0;
      }
    }

    if (amount <= 0.0) return null; // Couldn't parse a valid positive amount

    // 3. Extract Account/Card Last 4 digits
    String accountLast4 = '';
    final RegExp acctRegExp = RegExp(
      r'(?:a\/c|ac|account|card)\s*(?:no\.?)?\s*(?:ending)?\s*\*+([0-9]{3,4})',
      caseSensitive: false,
    );
    final acctMatch = acctRegExp.firstMatch(body);
    if (acctMatch != null && acctMatch.group(1) != null) {
      accountLast4 = acctMatch.group(1)!;
    }

    // 4. Extract Payee / Merchant Name
    String payee = 'Unknown Merchant';
    final RegExp payeeAtRegExp = RegExp(
      r'(?:at|vpa|to)\s+([A-Za-z0-9_\-\.\s]+?)(?=\.|\s+on|\s+ref|\s+avail|\s+bal|\s+link|\s*$)',
      caseSensitive: false,
    );
    final payeeMatch = payeeAtRegExp.firstMatch(body);
    if (payeeMatch != null && payeeMatch.group(1) != null) {
      final String candidate = payeeMatch.group(1)!.trim();
      if (candidate.length > 2 && candidate.length < 35) {
        payee = candidate;
      }
    }

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
}
