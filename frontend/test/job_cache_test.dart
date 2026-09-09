import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:remindbuddy/models/job_application.dart';
import 'package:remindbuddy/models/networking_lead.dart';

void main() {
  group('JobApplication Caching & JSON Serialization', () {
    test('JobApplication toJson -> jsonEncode -> fromJson roundtrip preserves all data', () {
      final now = DateTime.utc(2026, 9, 9, 10, 30, 0);
      final replyTime = DateTime.utc(2026, 9, 9, 11, 0, 0);

      final original = JobApplication(
        id: 'test_app_123',
        jobTitle: 'Senior DevOps Engineer',
        companyName: 'Tech Innovators',
        recipientEmail: 'jobs@techinnovators.com',
        extractedSkills: ['AWS', 'Kubernetes', 'Terraform'],
        generatedSubject: 'Application for Senior DevOps Engineer',
        generatedCoverLetter: 'Dear Hiring Manager...',
        status: 'sent',
        appliedAt: now,
        isAutoApplied: true,
        location: 'Bengaluru',
        experienceRequired: '2-4 Yrs',
        responseType: 'interview_invite',
        replyReceivedAt: replyTime,
        replySender: 'recruiter@techinnovators.com',
        replySubject: 'Interview Scheduled',
        replySnippet: 'We would love to talk to you.',
        replyBodyPreview: 'Hi Roshan, please choose a slot...',
        actionRequired: 'Book interview slot',
        isReplyDismissed: false,
        isBounced: false,
      );

      final jsonMap = original.toJson();
      final jsonString = jsonEncode(jsonMap);
      final decodedMap = jsonDecode(jsonString) as Map<String, dynamic>;
      final restored = JobApplication.fromJson(decodedMap);

      expect(restored.id, 'test_app_123');
      expect(restored.jobTitle, 'Senior DevOps Engineer');
      expect(restored.companyName, 'Tech Innovators');
      expect(restored.recipientEmail, 'jobs@techinnovators.com');
      expect(restored.extractedSkills, ['AWS', 'Kubernetes', 'Terraform']);
      expect(restored.isAutoApplied, true);
      expect(restored.appliedAt.toIso8601String(), now.toIso8601String());
      expect(restored.replyReceivedAt?.toIso8601String(), replyTime.toIso8601String());
      expect(restored.responseType, 'interview_invite');
    });

    test('JobApplication.fromMap supports alternative legacy field names', () {
      final legacyMap = {
        'role': 'Cloud Architect',
        'company': 'CloudScale Inc',
        'contactEmail': 'hr@cloudscale.com',
        'appliedAt': '2026-09-08T15:00:00.000Z',
        'autoApplied': true,
      };

      final restored = JobApplication.fromMap(legacyMap, 'legacy_doc_1');
      expect(restored.id, 'legacy_doc_1');
      expect(restored.jobTitle, 'Cloud Architect');
      expect(restored.companyName, 'CloudScale Inc');
      expect(restored.recipientEmail, 'hr@cloudscale.com');
      expect(restored.isAutoApplied, true);
      expect(restored.appliedAt.year, 2026);
    });
  });

  group('NetworkingLead Caching & JSON Serialization', () {
    test('NetworkingLead toJson -> jsonEncode -> fromJson roundtrip preserves all data', () {
      final now = DateTime.utc(2026, 9, 9, 10, 0, 0);
      final sentAt = DateTime.utc(2026, 9, 9, 10, 15, 0);

      final lead = NetworkingLead(
        id: 'lead_abc_456',
        name: 'Arjun Gupta',
        currentRole: 'CTO & Co-Founder',
        companyName: 'AI Startup Labs',
        location: 'Bengaluru, India',
        linkedinUrl: 'https://linkedin.com/in/arjungupta',
        email: 'arjun@aistartuplabs.com',
        category: 'founder',
        connectionNote: 'Hi Arjun, loved your recent update...',
        fullPitch: 'Dear Arjun, I noticed your tech team is expanding...',
        status: 'email_sent',
        discoveredAt: now,
        emailSent: true,
        emailSentAt: sentAt,
        emailSubject: 'DevOps & Cloud scaling collaboration',
        fundingStage: 'Series A',
        techStack: ['Node.js', 'Python', 'GCP'],
        isReplyDismissed: false,
        isBounced: false,
      );

      final jsonMap = lead.toJson();
      final jsonString = jsonEncode(jsonMap);
      final decodedMap = jsonDecode(jsonString) as Map<String, dynamic>;
      final restored = NetworkingLead.fromJson(decodedMap);

      expect(restored.id, 'lead_abc_456');
      expect(restored.name, 'Arjun Gupta');
      expect(restored.currentRole, 'CTO & Co-Founder');
      expect(restored.companyName, 'AI Startup Labs');
      expect(restored.discoveredAt.toIso8601String(), now.toIso8601String());
      expect(restored.emailSentAt?.toIso8601String(), sentAt.toIso8601String());
      expect(restored.emailSent, true);
      expect(restored.fundingStage, 'Series A');
      expect(restored.techStack, ['Node.js', 'Python', 'GCP']);
    });
  });
}
