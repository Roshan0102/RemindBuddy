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
}
