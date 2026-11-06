import 'package:flutter_test/flutter_test.dart';
import 'package:remindbuddy/services/job_assistant_service.dart';

void main() {
  group('CentralBlockedEmailInfo & CentrallyBlockedEmailException Tests', () {
    test('CentralBlockedEmailInfo parses standard bounce payload correctly', () {
      final now = DateTime(2026, 11, 6, 12, 0, 0);
      final rawData = {
        'companyName': 'Acme Corp',
        'reason': 'Address Not Found (550 / mailbox unavailable)',
        'isFake': false,
        'bouncedAt': now.toIso8601String(),
        'source': 'smtp_delivery_bounce',
        'reportedByUid': 'user_xyz',
      };

      final info = CentralBlockedEmailInfo.fromMap(rawData, 'hr@invalid-acme-domain.com');

      expect(info.email, 'hr@invalid-acme-domain.com');
      expect(info.companyName, 'Acme Corp');
      expect(info.reason, 'Address Not Found (550 / mailbox unavailable)');
      expect(info.isFake, false);
      expect(info.bouncedAt, now);
      expect(info.source, 'smtp_delivery_bounce');
      expect(info.reportedByUid, 'user_xyz');

      final serialized = info.toMap();
      expect(serialized['email'], 'hr@invalid-acme-domain.com');
      expect(serialized['companyName'], 'Acme Corp');
      expect(serialized['isFake'], false);
      expect(serialized['source'], 'smtp_delivery_bounce');
    });

    test('CentralBlockedEmailInfo parses fake scam report payload with defaults', () {
      final rawData = {
        'isFake': true,
        'reason': '',
      };

      final info = CentralBlockedEmailInfo.fromMap(rawData, 'scammer@fakehr.com');

      expect(info.email, 'scammer@fakehr.com');
      expect(info.isFake, true);
      expect(info.reason, 'Flagged as fraudulent recruiter / agency');
    });

    test('CentralBlockedEmailInfo defaults to invalid recipient when reason is empty and not fake', () {
      final rawData = {
        'isFake': false,
        'reason': '',
      };

      final info = CentralBlockedEmailInfo.fromMap(rawData, 'bounced@unknown.com');

      expect(info.email, 'bounced@unknown.com');
      expect(info.isFake, false);
      expect(info.reason, 'Invalid recipient mailbox / 550 delivery bounce');
    });

    test('CentrallyBlockedEmailException contains informative professional message', () {
      const info = CentralBlockedEmailInfo(
        email: 'invalid.hr@fakecorp.org',
        companyName: 'FakeCorp',
        reason: '550 User Unknown',
        isFake: false,
      );

      const exception = CentrallyBlockedEmailException(
        email: 'invalid.hr@fakecorp.org',
        info: info,
      );

      expect(exception.email, 'invalid.hr@fakecorp.org');
      expect(exception.info, info);
      expect(
        exception.toString(),
        contains('Recipient "invalid.hr@fakecorp.org" is blocked in Central Hub (550 User Unknown)'),
      );
    });
  });
}

