import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remindbuddy/services/email_verification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EmailVerificationService - Syntax & Baseline Validation', () {
    final service = EmailVerificationService();

    test('rejection for empty and malformed emails', () async {
      final emptyRes = await service.verifyEmail('');
      expect(emptyRes.isValid, isFalse);
      expect(emptyRes.isDeliverable, isFalse);
      expect(emptyRes.status, 'invalid');

      final whitespaceRes = await service.verifyEmail('   ');
      expect(whitespaceRes.isValid, isFalse);
      expect(whitespaceRes.isDeliverable, isFalse);

      final noAtRes = await service.verifyEmail('invalidrecruiteremail.com');
      expect(noAtRes.isValid, isFalse);
      expect(noAtRes.isDeliverable, isFalse);

      final syntaxRes = await service.verifyWithCodebaseValidator('bad@email@domain.com');
      expect(syntaxRes.isValid, isFalse);
      expect(syntaxRes.isDeliverable, isFalse);
      expect(syntaxRes.status, 'invalid_syntax');
    });

    test('rejection for disposable and burner domains in Tier 3', () async {
      final mailinatorRes = await service.verifyWithCodebaseValidator('hr@mailinator.com');
      expect(mailinatorRes.isValid, isFalse);
      expect(mailinatorRes.isDeliverable, isFalse);
      expect(mailinatorRes.status, 'disposable');
      expect(mailinatorRes.tierUsed, 'codebase_validator');

      final tempmailRes = await service.verifyWithCodebaseValidator('recruiter@tempmail.com');
      expect(tempmailRes.isValid, isFalse);
      expect(tempmailRes.isDeliverable, isFalse);
      expect(tempmailRes.status, 'disposable');
    });
  });

  group('EmailVerificationService - Tier 3 Codebase MX Validator (DoH)', () {
    final service = EmailVerificationService();

    test('resolves active MX records successfully via DoH', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host == 'dns.google' && request.url.queryParameters['type'] == 'MX') {
          return http.Response(
            jsonEncode({
              'Status': 0,
              'Answer': [
                {'name': 'google.com', 'type': 15, 'data': '10 aspmx.l.google.com.'}
              ]
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final hasMx = await service.checkDnsMxRecords('google.com', client: mockClient);
      expect(hasMx, isTrue);

      final result = await service.verifyWithCodebaseValidator('careers@google.com', client: mockClient);
      expect(result.isValid, isTrue);
      expect(result.isDeliverable, isTrue);
      expect(result.status, 'valid');
      expect(result.tierUsed, 'codebase_dns_mx');
    });

    test('detects missing MX records and suggests typo fix for gmail.co', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host == 'dns.google') {
          // No MX records found (Status: 3 or empty Answer)
          return http.Response(
            jsonEncode({'Status': 3, 'Answer': []}),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final result = await service.verifyWithCodebaseValidator('candidate@gmail.co', client: mockClient);
      expect(result.isValid, isFalse);
      expect(result.isDeliverable, isFalse);
      expect(result.status, 'no_mx_record');
      expect(result.suggestedEmail, 'candidate@gmail.com');
    });
  });

  group('EmailVerificationService - Tier 1 QuickEmailVerification API', () {
    final service = EmailVerificationService();

    test('correctly handles invalid mailbox from QuickEmailVerification', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host == 'api.quickemailverification.com') {
          return http.Response(
            jsonEncode({
              'result': 'invalid',
              'reason': 'rejected_email',
              'safe_to_send': 'false',
              'did_you_mean': '',
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final result = await service.verifyWithQuickEmailVerification('fake@nonexistent.com', 'test_key', client: mockClient);
      expect(result, isNotNull);
      expect(result!.isValid, isFalse);
      expect(result.isDeliverable, isFalse);
      expect(result.status, 'invalid');
      expect(result.reason, 'rejected_email');
      expect(result.tierUsed, 'quickemailverification');
    });

    test('correctly handles deliverable mailbox from QuickEmailVerification', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host == 'api.quickemailverification.com') {
          return http.Response(
            jsonEncode({
              'result': 'valid',
              'reason': 'valid_mailbox',
              'safe_to_send': 'true',
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final result = await service.verifyWithQuickEmailVerification('recruiter@company.com', 'test_key', client: mockClient);
      expect(result, isNotNull);
      expect(result!.isValid, isTrue);
      expect(result.isDeliverable, isTrue);
      expect(result.status, 'valid');
      expect(result.tierUsed, 'quickemailverification');
    });

    test('returns null on quota exceeded (HTTP 402/429) to trigger cascading', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Quota Exceeded', 402);
      });

      final result = await service.verifyWithQuickEmailVerification('test@company.com', 'test_key', client: mockClient);
      expect(result, isNull);
    });
  });

  group('EmailVerificationService - Tier 2 Reoon Email Verifier API', () {
    final service = EmailVerificationService();

    test('correctly flags spamtrap or invalid status from Reoon', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host == 'emailverifier.reoon.com') {
          return http.Response(
            jsonEncode({
              'status': 'spamtrap',
              'is_safe_to_send': false,
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final result = await service.verifyWithReoon('trap@scam.com', 'reoon_test_key', client: mockClient);
      expect(result, isNotNull);
      expect(result!.isValid, isFalse);
      expect(result.isDeliverable, isFalse);
      expect(result.status, 'spamtrap');
      expect(result.tierUsed, 'reoon');
    });

    test('correctly flags valid status from Reoon', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host == 'emailverifier.reoon.com') {
          return http.Response(
            jsonEncode({
              'status': 'valid',
              'is_safe_to_send': true,
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final result = await service.verifyWithReoon('valid@enterprise.org', 'reoon_test_key', client: mockClient);
      expect(result, isNotNull);
      expect(result!.isValid, isTrue);
      expect(result.isDeliverable, isTrue);
      expect(result.status, 'valid');
      expect(result.tierUsed, 'reoon');
    });
  });

  group('EmailVerificationService - Cascading Fallback Integration', () {
    test('cascades from Tier 1 (quota exhausted) -> Tier 2 (quota exhausted) -> Tier 3 (Codebase MX)', () async {
      final service = EmailVerificationService();

      final mockClient = MockClient((request) async {
        // QuickEmailVerification gives 429
        if (request.url.host == 'api.quickemailverification.com') {
          return http.Response('Rate limit', 429);
        }
        // Reoon gives 500 error
        if (request.url.host == 'emailverifier.reoon.com') {
          return http.Response('Internal error', 500);
        }
        // Google DoH returns active MX
        if (request.url.host == 'dns.google') {
          return http.Response(
            jsonEncode({
              'Status': 0,
              'Answer': [
                {'name': 'validcompany.com', 'type': 15, 'data': '10 mail.validcompany.com.'}
              ]
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final result = await service.verifyEmail('jobs@validcompany.com', client: mockClient);
      expect(result.isValid, isTrue);
      expect(result.isDeliverable, isTrue);
      expect(result.tierUsed, 'codebase_dns_mx');
    });
  });
}
