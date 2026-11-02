import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Result object returned by the multi-tier EmailVerificationService.
class EmailVerificationResult {
  final bool isValid;
  final bool isDeliverable;
  final String status; // 'valid', 'invalid', 'risky', 'blocked', 'unknown'
  final String reason;
  final String tierUsed; // 'blacklist', 'quickemailverification', 'reoon', 'codebase_validator'
  final String? suggestedEmail; // did_you_mean typo suggestion
  final Map<String, dynamic> rawDetails;

  const EmailVerificationResult({
    required this.isValid,
    required this.isDeliverable,
    required this.status,
    required this.reason,
    required this.tierUsed,
    this.suggestedEmail,
    this.rawDetails = const {},
  });

  @override
  String toString() =>
      'EmailVerificationResult(isDeliverable: $isDeliverable, status: $status, tier: $tierUsed, reason: $reason, suggested: $suggestedEmail)';
}

/// Robust 4-tier Cascading Email Verification Service:
/// Tier 0: Central Blacklist & User's Blocked Fake Jobs (Firestore)
/// Tier 1: QuickEmailVerification API (User key -> Default key)
/// Tier 2: Reoon Email Verifier API (User key)
/// Tier 3: In-House Codebase Validator (RFC 5322 regex, Disposable blocklist, DoH Google DNS MX resolution)
class EmailVerificationService {
  static final EmailVerificationService _instance = EmailVerificationService._internal();
  factory EmailVerificationService() => _instance;
  EmailVerificationService._internal();

  /// Default QuickEmailVerification API key provided as baseline fallback
  static const String defaultQuickEmailVerificationKey =
      '2529d041c40e78fcf13255ace55b3d48e020e710886fbcea6e536ad9de40';

  static const List<String> _disposableDomains = [
    'mailinator.com',
    'guerrillamail.com',
    '10minutemail.com',
    'tempmail.com',
    'temp-mail.org',
    'throwawaymail.com',
    'yopmail.com',
    'sharklasers.com',
    'trashmail.com',
    'dispostable.com',
    'fakeinbox.com',
    'getairmail.com',
    'maildrop.cc',
    'mohmal.com',
    'generator.email',
  ];

  /// Verifies deliverability of an email address across the cascading tiers.
  Future<EmailVerificationResult> verifyEmail(String email, {String? targetUid, http.Client? client}) async {
    final cleanEmail = email.toLowerCase().trim();
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      return const EmailVerificationResult(
        isValid: false,
        isDeliverable: false,
        status: 'invalid',
        reason: 'Empty or malformed email address',
        tierUsed: 'syntax',
      );
    }

    String? uid = targetUid;
    if (uid == null) {
      try {
        uid = FirebaseAuth.instance.currentUser?.uid;
      } catch (_) {}
    }

    // ========================================================================
    // TIER 0: Central Blacklist & User Blocked Fake Jobs
    // ========================================================================
    final blacklistResult = await _checkBlacklistAndFakeJobs(cleanEmail, uid);
    if (blacklistResult != null) {
      debugPrint('[EmailVerification] Tier 0 matched: $blacklistResult');
      return blacklistResult;
    }

    // Load user API keys from Firestore
    final userKeys = await _loadUserApiKeys(uid);
    final userQevKey = (userKeys['quickEmailVerificationApiKey'] ?? '').toString().trim();
    final activeQevKey = userQevKey.isNotEmpty ? userQevKey : defaultQuickEmailVerificationKey;
    final userReoonKey = (userKeys['reoonApiKey'] ?? userKeys['reoonEmailVerifierApiKey'] ?? '').toString().trim();

    // ========================================================================
    // TIER 1: QuickEmailVerification API
    // ========================================================================
    if (activeQevKey.isNotEmpty) {
      final qevResult = await _verifyWithQuickEmailVerification(cleanEmail, activeQevKey, client: client);
      if (qevResult != null) {
        debugPrint('[EmailVerification] Tier 1 QuickEmailVerification resolved: $qevResult');
        return qevResult;
      }
      debugPrint('[EmailVerification] Tier 1 QuickEmailVerification failed or quota exhausted, cascading to Tier 2...');
    }

    // ========================================================================
    // TIER 2: Reoon Email Verifier API
    // ========================================================================
    if (userReoonKey.isNotEmpty) {
      final reoonResult = await _verifyWithReoon(cleanEmail, userReoonKey, client: client);
      if (reoonResult != null) {
        debugPrint('[EmailVerification] Tier 2 Reoon resolved: $reoonResult');
        return reoonResult;
      }
      debugPrint('[EmailVerification] Tier 2 Reoon failed or quota exhausted, cascading to Tier 3...');
    }

    // ========================================================================
    // TIER 3: In-House Codebase Validator (RFC Regex + Disposable + DoH DNS MX)
    // ========================================================================
    debugPrint('[EmailVerification] Running Tier 3 In-House Codebase Validator for $cleanEmail');
    return await _verifyWithCodebaseValidator(cleanEmail, client: client);
  }

  // --------------------------------------------------------------------------
  // Testing hooks
  // --------------------------------------------------------------------------
  @visibleForTesting
  Future<EmailVerificationResult?> verifyWithQuickEmailVerification(String cleanEmail, String apiKey, {http.Client? client}) =>
      _verifyWithQuickEmailVerification(cleanEmail, apiKey, client: client);

  @visibleForTesting
  Future<EmailVerificationResult?> verifyWithReoon(String cleanEmail, String apiKey, {http.Client? client}) =>
      _verifyWithReoon(cleanEmail, apiKey, client: client);

  @visibleForTesting
  Future<EmailVerificationResult> verifyWithCodebaseValidator(String cleanEmail, {http.Client? client}) =>
      _verifyWithCodebaseValidator(cleanEmail, client: client);

  @visibleForTesting
  Future<bool> checkDnsMxRecords(String domain, {http.Client? client}) =>
      _checkDnsMxRecords(domain, client: client);

  @visibleForTesting
  static List<String> get disposableDomains => _disposableDomains;

  // --------------------------------------------------------------------------
  // Tier 0 Implementation: Blacklist & Blocked Fake Jobs
  // --------------------------------------------------------------------------
  Future<EmailVerificationResult?> _checkBlacklistAndFakeJobs(String cleanEmail, String? uid) async {
    try {
      final db = FirebaseFirestore.instance;
      final encoded = Uri.encodeComponent(cleanEmail);

      // Check system_bounced_emails
      final bouncedDoc = await db.collection('system_bounced_emails').doc(encoded).get();
      if (bouncedDoc.exists) {
        return EmailVerificationResult(
          isValid: false,
          isDeliverable: false,
          status: 'blocked',
          reason: 'Address previously bounced in system (550 / Address Not Found)',
          tierUsed: 'blacklist',
          rawDetails: bouncedDoc.data() ?? {},
        );
      }

      // Check user's blocked_fake_jobs
      if (uid != null && uid.isNotEmpty) {
        final fakeDoc = await db.collection('users').doc(uid).collection('blocked_fake_jobs').doc(encoded).get();
        if (fakeDoc.exists) {
          final data = fakeDoc.data() ?? {};
          final reason = data['reason'] ?? 'Marked as fake/scam job';
          return EmailVerificationResult(
            isValid: false,
            isDeliverable: false,
            status: 'blocked',
            reason: 'Permanently blocked by you: $reason',
            tierUsed: 'blacklist',
            rawDetails: data,
          );
        }
      }
    } catch (e) {
      debugPrint('[EmailVerification] Notice checking blacklist in Tier 0: $e');
    }
    return null;
  }

  // --------------------------------------------------------------------------
  // Tier 1 Implementation: QuickEmailVerification API
  // --------------------------------------------------------------------------
  Future<EmailVerificationResult?> _verifyWithQuickEmailVerification(String cleanEmail, String apiKey, {http.Client? client}) async {
    try {
      final uri = Uri.parse(
        'https://api.quickemailverification.com/v1/verify?email=${Uri.encodeComponent(cleanEmail)}&apikey=$apiKey',
      );
      final response = client != null
          ? await client.get(uri).timeout(const Duration(seconds: 8))
          : await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final result = (data['result'] ?? '').toString().toLowerCase();
        final safeToSendStr = (data['safe_to_send'] ?? '').toString().toLowerCase();
        final isSafeToSend = safeToSendStr == 'true';
        final reason = (data['reason'] ?? '').toString();
        final didYouMean = (data['did_you_mean'] ?? '').toString().trim();

        // If definitely invalid or unsafe to send
        if (result == 'invalid' || !isSafeToSend) {
          return EmailVerificationResult(
            isValid: false,
            isDeliverable: false,
            status: result.isNotEmpty ? result : 'invalid',
            reason: reason.isNotEmpty ? reason : 'Unsafe to send / rejected',
            tierUsed: 'quickemailverification',
            suggestedEmail: didYouMean.isNotEmpty ? didYouMean : null,
            rawDetails: data,
          );
        }

        // If valid and safe to send
        if (result == 'valid' && isSafeToSend) {
          return EmailVerificationResult(
            isValid: true,
            isDeliverable: true,
            status: 'valid',
            reason: reason.isNotEmpty ? reason : 'Verified deliverable mailbox',
            tierUsed: 'quickemailverification',
            rawDetails: data,
          );
        }

        // If result is unknown / temporary failure, return null to cascade to next tier
        return null;
      } else if (response.statusCode == 402 || response.statusCode == 429) {
        debugPrint('[EmailVerification] QuickEmailVerification quota limit reached (HTTP ${response.statusCode})');
        return null; // Cascade to next tier
      } else {
        debugPrint('[EmailVerification] QuickEmailVerification HTTP error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('[EmailVerification] QuickEmailVerification exception: $e');
      return null;
    }
  }

  // --------------------------------------------------------------------------
  // Tier 2 Implementation: Reoon Email Verifier API
  // --------------------------------------------------------------------------
  Future<EmailVerificationResult?> _verifyWithReoon(String cleanEmail, String apiKey, {http.Client? client}) async {
    try {
      final uri = Uri.parse(
        'https://emailverifier.reoon.com/api/v1/verify?email=${Uri.encodeComponent(cleanEmail)}&key=$apiKey&mode=power',
      );
      final response = client != null
          ? await client.get(uri).timeout(const Duration(seconds: 8))
          : await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final status = (data['status'] ?? '').toString().toLowerCase();
        final isSafeToSend = data['is_safe_to_send'] == true || data['is_safe_to_send'] == 'true';

        if (status == 'invalid' || status == 'disposable' || status == 'spamtrap' || !isSafeToSend) {
          return EmailVerificationResult(
            isValid: false,
            isDeliverable: false,
            status: status.isNotEmpty ? status : 'invalid',
            reason: 'Reoon flagged as $status (is_safe_to_send: $isSafeToSend)',
            tierUsed: 'reoon',
            rawDetails: data,
          );
        }

        if (status == 'valid' && isSafeToSend) {
          return EmailVerificationResult(
            isValid: true,
            isDeliverable: true,
            status: 'valid',
            reason: 'Reoon verified deliverable',
            tierUsed: 'reoon',
            rawDetails: data,
          );
        }

        return null; // Unknown or catch_all without certainty -> cascade to Tier 3
      } else {
        debugPrint('[EmailVerification] Reoon HTTP error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('[EmailVerification] Reoon exception: $e');
      return null;
    }
  }

  // --------------------------------------------------------------------------
  // Tier 3 Implementation: In-House Codebase Validator
  // --------------------------------------------------------------------------
  Future<EmailVerificationResult> _verifyWithCodebaseValidator(String cleanEmail, {http.Client? client}) async {
    // 1. RFC 5322 Syntax Regex
    final emailRegex = RegExp(
      r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$",
    );
    if (!emailRegex.hasMatch(cleanEmail)) {
      return const EmailVerificationResult(
        isValid: false,
        isDeliverable: false,
        status: 'invalid_syntax',
        reason: 'Invalid email syntax format (RFC 5322)',
        tierUsed: 'codebase_validator',
      );
    }

    final parts = cleanEmail.split('@');
    final domain = parts.length == 2 ? parts[1].trim() : '';
    if (domain.isEmpty) {
      return const EmailVerificationResult(
        isValid: false,
        isDeliverable: false,
        status: 'invalid_domain',
        reason: 'Missing email domain',
        tierUsed: 'codebase_validator',
      );
    }

    // 2. Disposable / Burner Domain Blocklist Check
    if (_disposableDomains.contains(domain)) {
      return EmailVerificationResult(
        isValid: false,
        isDeliverable: false,
        status: 'disposable',
        reason: 'Temporary / disposable email domain ($domain) blocked',
        tierUsed: 'codebase_validator',
      );
    }

    // 3. Real-Time DNS MX Resolution via Google DNS-over-HTTPS (DoH)
    final hasMx = await _checkDnsMxRecords(domain, client: client);
    if (!hasMx) {
      // Check for common typo (e.g. gmail.co -> gmail.com)
      String? typoSuggestion;
      if (domain == 'gmail.co') {
        typoSuggestion = '${parts[0]}@gmail.com';
      } else if (domain == 'gmai.com' || domain == 'gmial.com') {
        typoSuggestion = '${parts[0]}@gmail.com';
      }

      return EmailVerificationResult(
        isValid: false,
        isDeliverable: false,
        status: 'no_mx_record',
        reason: 'Domain $domain has no active Mail Exchange (MX) records and cannot receive email',
        tierUsed: 'codebase_dns_mx',
        suggestedEmail: typoSuggestion,
      );
    }

    // Passed format, not disposable, and active MX records confirmed
    return EmailVerificationResult(
      isValid: true,
      isDeliverable: true,
      status: 'valid',
      reason: 'Syntax valid, active MX records resolved for $domain',
      tierUsed: 'codebase_dns_mx',
      rawDetails: {'domain': domain, 'hasMx': true},
    );
  }

  /// Queries Google DNS-over-HTTPS for MX records on port 443 (100% cloud-safe, no port 25 or port 53 blocks).
  Future<bool> _checkDnsMxRecords(String domain, {http.Client? client}) async {
    try {
      final uri = Uri.parse('https://dns.google/resolve?name=${Uri.encodeComponent(domain)}&type=MX');
      final res = client != null
          ? await client.get(uri).timeout(const Duration(seconds: 5))
          : await http.get(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final status = json['Status'];
        final answer = json['Answer'] as List<dynamic>?;
        if (status == 0 && answer != null && answer.isNotEmpty) {
          return true; // Found active MX records
        }
        // Authoritative response from Google DNS: domain has no active MX records
        return false;
      }
    } catch (e) {
      debugPrint('[EmailVerification] Google DoH lookup notice for $domain: $e');
    }

    // Fallback: Check standard host lookup
    try {
      if (!kIsWeb) {
        final lookup = await InternetAddress.lookup(domain).timeout(const Duration(seconds: 4));
        return lookup.isNotEmpty;
      }
    } catch (_) {}

    return false;
  }

  /// Helper to load user API keys from Firestore
  Future<Map<String, dynamic>> _loadUserApiKeys(String? uid) async {
    if (uid == null || uid.isEmpty) return {};
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final userKeys = data['userApiKeys'] as Map<String, dynamic>? ?? {};
        return {
          ...data,
          ...userKeys,
        };
      }
    } catch (e) {
      debugPrint('[EmailVerification] Error loading userApiKeys: $e');
    }
    return {};
  }
}
