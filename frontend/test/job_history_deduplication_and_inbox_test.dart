import 'package:flutter_test/flutter_test.dart';
import 'package:remindbuddy/models/job_application.dart';
import 'package:remindbuddy/screens/job_replies_screen.dart';

void main() {
  group('Unified Job History Deduplication & Data Model Tests', () {
    test('JobApplication correctly serializes and deserializes tailoredResume fields', () {
      final now = DateTime.now();
      final app = JobApplication(
        id: 'app_123',
        jobTitle: 'DevOps Engineer',
        companyName: 'Karini AI',
        recipientEmail: 'careers@karini.ai',
        extractedSkills: ['Docker', 'Kubernetes', 'Terraform'],
        generatedSubject: 'Application for DevOps Engineer - Candidate',
        generatedCoverLetter: 'Dear Hiring Team,\n\nI am excited to apply.',
        status: 'bounced',
        appliedAt: now,
        isBounced: true,
        tailoredResumePdfBase64: 'JVBERi0xLjQKJcfs...',
        tailoredResumePdfUrl: 'https://storage.googleapis.com/test-bucket/tailored.pdf',
      );

      final map = app.toMap();
      expect(map['id'], 'app_123');
      expect(map['tailoredResumePdfBase64'], 'JVBERi0xLjQKJcfs...');
      expect(map['tailoredResumePdfUrl'], 'https://storage.googleapis.com/test-bucket/tailored.pdf');
      expect(map['isBounced'], true);

      final fromMapApp = JobApplication.fromMap(map, 'app_123');
      expect(fromMapApp.id, 'app_123');
      expect(fromMapApp.jobTitle, 'DevOps Engineer');
      expect(fromMapApp.companyName, 'Karini AI');
      expect(fromMapApp.recipientEmail, 'careers@karini.ai');
      expect(fromMapApp.isBounced, true);
      expect(fromMapApp.tailoredResumePdfBase64, 'JVBERi0xLjQKJcfs...');
      expect(fromMapApp.tailoredResumePdfUrl, 'https://storage.googleapis.com/test-bucket/tailored.pdf');
    });

    test('JobApplication copyWith correctly updates tailored resume attributes', () {
      final app = JobApplication(
        id: 'share_101',
        jobTitle: 'Software Engineer',
        companyName: 'LeapGen AI',
        recipientEmail: 'recruiter@leapgen.ai',
        extractedSkills: ['Flutter', 'Dart'],
        generatedSubject: 'Application',
        generatedCoverLetter: 'Cover Letter',
        status: 'extracted',
        appliedAt: DateTime.now(),
      );

      final updated = app.copyWith(
        tailoredResumePdfBase64: 'base64_data_xyz',
        tailoredResumePdfUrl: 'https://example.com/resume.pdf',
      );

      expect(updated.tailoredResumePdfBase64, 'base64_data_xyz');
      expect(updated.tailoredResumePdfUrl, 'https://example.com/resume.pdf');
    });

    test('Semantic deduplication merges duplicate applications and preserves bounce state', () {
      final now = DateTime.now();
      final duplicateA = JobApplication(
        id: 'doc_A',
        jobTitle: 'DevOps Engineer',
        companyName: 'Karini AI',
        recipientEmail: 'careers@karini.ai',
        extractedSkills: ['AWS', 'K8s'],
        generatedSubject: 'Subj A',
        generatedCoverLetter: 'Body A',
        status: 'needs_review',
        appliedAt: now,
        isBounced: false,
      );

      final duplicateB = JobApplication(
        id: 'doc_B',
        jobTitle: 'DevOps Engineer',
        companyName: 'Karini AI',
        recipientEmail: 'careers@karini.ai',
        extractedSkills: ['AWS', 'K8s'],
        generatedSubject: 'Subj B',
        generatedCoverLetter: 'Body B',
        status: 'bounced',
        appliedAt: now.add(const Duration(seconds: 2)),
        isBounced: true,
        errorMessage: '550 Address Not Found',
      );

      final rawApps = [duplicateA, duplicateB];
      final Map<String, JobApplication> unifiedMap = {};
      final Map<String, List<String>> duplicateDocIds = {};

      for (final app in rawApps) {
        final normComp = app.companyName.toLowerCase().trim();
        final normTitle = app.jobTitle.toLowerCase().trim();
        final normEmail = app.recipientEmail.toLowerCase().trim();

        String? matchKey;
        for (final key in unifiedMap.keys) {
          final existing = unifiedMap[key]!;
          final exComp = existing.companyName.toLowerCase().trim();
          final exTitle = existing.jobTitle.toLowerCase().trim();
          final exEmail = existing.recipientEmail.toLowerCase().trim();

          final isSameTarget = normComp.isNotEmpty &&
              exComp == normComp &&
              (normTitle == exTitle || normTitle.contains(exTitle) || exTitle.contains(normTitle)) &&
              (normEmail.isEmpty || exEmail.isEmpty || normEmail == exEmail);

          if (isSameTarget) {
            final timeDiff = existing.appliedAt.difference(app.appliedAt).abs();
            if (timeDiff.inHours < 24) {
              matchKey = key;
              break;
            }
          }
        }

        if (matchKey != null) {
          final k = matchKey;
          duplicateDocIds.putIfAbsent(k, () => [k]).add(app.id);
          final existing = unifiedMap[k]!;

          final preferApp = (app.isBounced && !existing.isBounced) ||
              (app.status == 'bounced' && existing.status != 'bounced') ||
              (app.tailoredResumePdfBase64 != null && existing.tailoredResumePdfBase64 == null) ||
              ((app.errorMessage?.isNotEmpty ?? false) && (existing.errorMessage?.isEmpty ?? true));

          if (preferApp) {
            unifiedMap[k] = app.copyWith(id: k);
          }
        } else {
          unifiedMap[app.id] = app;
          duplicateDocIds[app.id] = [app.id];
        }
      }

      // Verify that deduplication reduced 2 records into 1 unified record
      expect(unifiedMap.length, 1);
      final singleResult = unifiedMap.values.first;
      expect(singleResult.companyName, 'Karini AI');
      expect(singleResult.isBounced, true);
      expect(singleResult.status, 'bounced');

      // Verify that duplicate IDs tracking contains both document IDs for clean deletion
      expect(duplicateDocIds['doc_A'], containsAll(['doc_A', 'doc_B']));
    });
  });

  group('Recruiter Replies Inbox Filtering & Deduplication Tests', () {
    test('Bounced and Address Not Found items are strictly excluded from replies inbox', () {
      final now = DateTime.now();

      final legitReply = JobApplication(
        id: 'reply_1',
        jobTitle: 'Senior Flutter Developer',
        companyName: 'Google',
        recipientEmail: 'recruiter@google.com',
        extractedSkills: ['Flutter'],
        generatedSubject: 'Application',
        generatedCoverLetter: 'Cover Letter',
        status: 'reply_received',
        responseType: 'interview_invite',
        replyReceivedAt: now,
        replySubject: 'Invitation for technical screen',
        replySnippet: 'We would love to schedule a call.',
        appliedAt: now.subtract(const Duration(days: 2)),
      );

      final bouncedApp1 = JobApplication(
        id: 'bounce_1',
        jobTitle: 'DevOps Engineer',
        companyName: 'Karini AI',
        recipientEmail: 'careers@karini.ai',
        extractedSkills: ['Docker'],
        generatedSubject: 'Application',
        generatedCoverLetter: 'Cover Letter',
        status: 'bounced',
        responseType: 'address_not_found',
        isBounced: true,
        appliedAt: now,
      );

      final bouncedApp2 = JobApplication(
        id: 'bounce_2',
        jobTitle: 'Backend Engineer',
        companyName: 'DeadMail Inc',
        recipientEmail: 'hr@deadmail.fake',
        extractedSkills: ['Node.js'],
        generatedSubject: 'Application',
        generatedCoverLetter: 'Cover Letter',
        status: 'reply_received', // even if status was set to reply_received by daemon
        responseType: 'bounced',
        replySender: 'mailer-daemon@googlemail.com',
        replySubject: 'Delivery Status Notification (Failure)',
        isBounced: true,
        appliedAt: now,
      );

      final allApps = [legitReply, bouncedApp1, bouncedApp2];

      // Replicate inbox filter logic
      bool isDeliveryBounce(String sender, String subject, String bodySnippet, String? responseType) {
        if (responseType == 'bounced') return true;
        final s = sender.toLowerCase();
        final sub = subject.toLowerCase();
        final b = bodySnippet.toLowerCase();
        return s.contains('mailer-daemon') ||
            s.contains('postmaster') ||
            s.contains('delivery subsystem') ||
            sub.contains('delivery status notification') ||
            sub.contains('address not found') ||
            sub.contains('failure notice') ||
            sub.contains('could not be delivered') ||
            b.contains("address couldn't be found") ||
            b.contains('address could not be found') ||
            b.contains('recipient address rejected') ||
            b.contains('delivery failure');
      }

      final appReplies = allApps.where((a) {
        if (a.replyDeleted || a.isBounced) return false;
        if (a.status != 'reply_received') return false;
        if (a.responseType == 'bounced' || a.responseType == 'address_not_found') return false;
        if (isDeliveryBounce(a.replySender ?? '', a.replySubject ?? '', a.replySnippet ?? '', a.responseType)) return false;
        return true;
      }).toList();

      expect(appReplies.length, 1);
      expect(appReplies.first.id, 'reply_1');
      expect(appReplies.first.companyName, 'Google');
      expect(appReplies.first.responseType, 'interview_invite');
    });

    test('Duplicate recruiter replies are deduplicated in inbox list', () {
      final now = DateTime.now();

      final replyA = JobApplication(
        id: 'app_doc_1',
        jobTitle: 'Staff Engineer',
        companyName: 'Acme Corp',
        recipientEmail: 'talent@acme.com',
        extractedSkills: ['System Design'],
        generatedSubject: 'Application',
        generatedCoverLetter: 'Cover Letter',
        status: 'reply_received',
        responseType: 'founder_chat',
        replyReceivedAt: now,
        replySubject: 'Re: Application - Candidate',
        replySnippet: 'Excited to chat this week.',
        appliedAt: now.subtract(const Duration(days: 1)),
      );

      final replyB = JobApplication(
        id: 'app_doc_2', // duplicate doc for same application & reply
        jobTitle: 'Staff Engineer',
        companyName: 'Acme Corp',
        recipientEmail: 'talent@acme.com',
        extractedSkills: ['System Design'],
        generatedSubject: 'Application',
        generatedCoverLetter: 'Cover Letter',
        status: 'reply_received',
        responseType: 'founder_chat',
        replyReceivedAt: now,
        replySubject: 'Re: Application - Candidate',
        replySnippet: 'Excited to chat this week.',
        appliedAt: now.subtract(const Duration(days: 1)),
      );

      final appReplies = [replyA, replyB];

      final Set<String> seenReplyKeys = {};
      final List<UnifiedReplyItem> unifiedReplies = [];

      for (final a in appReplies) {
        final dateKey = a.replyReceivedAt != null ? '${a.replyReceivedAt!.year}-${a.replyReceivedAt!.month}-${a.replyReceivedAt!.day}' : '';
        final key = '${a.companyName.toLowerCase().trim()}|${a.recipientEmail.toLowerCase().trim()}|$dateKey|${(a.replySubject ?? a.generatedSubject).toLowerCase().trim()}';
        if (!seenReplyKeys.contains(key)) {
          seenReplyKeys.add(key);
          unifiedReplies.add(UnifiedReplyItem(
            id: a.id,
            isStartupLead: false,
            companyName: a.companyName,
            roleOrTitle: a.jobTitle,
            recipientEmail: a.recipientEmail,
            senderNameOrEmail: a.replySender ?? a.recipientEmail,
            subject: a.replySubject ?? a.generatedSubject,
            responseType: a.responseType ?? 'hr_query',
            summary: a.replySnippet ?? 'Recruiter replied to your application.',
            bodyPreview: a.replyBodyPreview ?? '',
            actionRequired: a.actionRequired ?? 'Check your email',
            receivedAt: a.replyReceivedAt ?? a.appliedAt,
            isDismissed: a.isReplyDismissed,
            isBounced: false,
          ));
        }
      }

      expect(unifiedReplies.length, 1);
      expect(unifiedReplies.first.companyName, 'Acme Corp');
      expect(unifiedReplies.first.responseType, 'founder_chat');
    });
  });
}
