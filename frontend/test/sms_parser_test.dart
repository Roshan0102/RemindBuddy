import 'package:flutter_test/flutter_test.dart';
import 'package:remindbuddy/services/sms_parser_service.dart';

void main() {
  test('Parses HDFC debit SMS with dispute footer correctly', () {
    const sender = 'AD-HDFCBK';
    const body = '''Sent Rs.1.00
From HDFC Bank A/C *0623
To PRUTHVIRAJ K G
On 25/08/26
Ref 128505104635
Not You?
Call 18002586161/SMS BLOCK UPI to 7308080808''';

    final result = SmsParserService.parseSms(sender, body, 1787680000000);

    expect(result, isNotNull);
    expect(result!.bankName, 'HDFC Bank');
    expect(result.accountLast4, '0623');
    expect(result.amount, 1.0);
    expect(result.type, 'Debit');
    expect(result.payee, 'Pruthviraj K G');
  });

  test('Parses unknown SMS header with custom user bank mapping', () {
    const sender = 'BV-INDBNK-S';
    const body = 'Debited Rs. 500.00 from A/C *1234 on 27/08/26 to SWIGGY.';
    final customMappings = {'BV-INDBNK-S': 'Indian Bank'};

    final result = SmsParserService.parseSms(sender, body, 1787680000000, customMappings);

    expect(result, isNotNull);
    expect(result!.bankName, 'Indian Bank');
    expect(result.accountLast4, '1234');
    expect(result.amount, 500.0);
    expect(result.type, 'Debit');
  });

  test('Ignores failed or unsuccessful transaction SMS', () {
    const sender = 'AD-ZEPTO';
    const body = 'Payment of Rs 350.00 to ZEPTO failed on 26/08/26. Please try again.';

    final result = SmsParserService.parseSms(sender, body, 1787680000000);

    expect(result, isNull);
  });
}
