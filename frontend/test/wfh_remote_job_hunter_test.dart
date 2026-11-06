import 'package:flutter_test/flutter_test.dart';
import 'package:remindbuddy/models/job_application.dart';

void main() {
  group('WFH Remote Job Hunter Unit Tests', () {
    test('JobApplication correctly deserializes and identifies WFH remote application', () {
      final map = {
        'id': 'wfh_job_123',
        'jobTitle': 'Senior Flutter Engineer',
        'companyName': 'RemoteTech Global',
        'recipientEmail': 'recruiter@remotetech.io',
        'extractedSkills': ['Flutter', 'Dart', 'Firebase'],
        'generatedSubject': 'Application for Senior Flutter Engineer (Remote) - John Doe',
        'generatedCoverLetter': 'Dear Hiring Team,\n\nI am eager to contribute as Senior Flutter Engineer.\n\nSincerely,\nJohn Doe',
        'status': 'sent',
        'appliedAt': '2026-11-06T10:00:00.000Z',
        'source': 'wfh_remote',
        'sourcePlatform': 'WFH Remote Job Hunter 🏠',
        'isAutoApplied': true,
        'location': 'India (Remote)',
        'isRemote': true,
        'wfhLocation': 'India',
        'tailoredResumePdfBase64': 'JVBERi0xLjQK...',
      };

      final app = JobApplication.fromMap(map, 'wfh_job_123');

      expect(app.id, 'wfh_job_123');
      expect(app.source, 'wfh_remote');
      expect(app.sourcePlatform, 'WFH Remote Job Hunter 🏠');
      expect(app.isRemote, isTrue);
      expect(app.wfhLocation, 'India');
      expect(app.location, 'India (Remote)');
      expect(app.recipientEmail, 'recruiter@remotetech.io');
      expect(app.tailoredResumePdfBase64, 'JVBERi0xLjQK...');
    });

    test('JobApplication toMap retains WFH Remote fields', () {
      final app = JobApplication(
        id: 'wfh_job_456',
        jobTitle: 'Fullstack Dev',
        companyName: 'Acme Corp',
        recipientEmail: 'jobs@acme.com',
        extractedSkills: ['Node.js', 'React'],
        generatedSubject: 'Application for Fullstack Dev (Remote)',
        generatedCoverLetter: 'Cover letter content...',
        status: 'sent',
        appliedAt: DateTime(2026, 11, 6),
        source: 'wfh_remote',
        sourcePlatform: 'WFH Remote Job Hunter 🏠',
        isRemote: true,
        wfhLocation: 'United States',
        location: 'United States (Remote)',
        isAutoApplied: true,
      );

      final map = app.toMap();

      expect(map['id'], 'wfh_job_456');
      expect(map['source'], 'wfh_remote');
      expect(map['isRemote'], isTrue);
      expect(map['wfhLocation'], 'United States');
      expect(map['location'], 'United States (Remote)');
    });

    test('JobApplication copyWith properly updates WFH Remote location', () {
      final app = JobApplication(
        id: 'wfh_job_789',
        jobTitle: 'Backend Engineer',
        companyName: 'CloudScale',
        recipientEmail: 'hr@cloudscale.io',
        extractedSkills: ['Go', 'Kubernetes'],
        generatedSubject: 'Application for Backend Engineer',
        generatedCoverLetter: 'Body...',
        status: 'sent',
        appliedAt: DateTime.now(),
        source: 'wfh_remote',
        isRemote: true,
        wfhLocation: 'India',
      );

      final updated = app.copyWith(
        wfhLocation: 'Worldwide',
        location: 'Worldwide (Remote)',
      );

      expect(updated.wfhLocation, 'Worldwide');
      expect(updated.location, 'Worldwide (Remote)');
      expect(updated.source, 'wfh_remote');
      expect(updated.isRemote, isTrue);
    });

    test('WFH search query formulation handles country vs worldwide correctly', () {
      String buildQuery(String role, String loc) {
        final isWorldwide = loc.toLowerCase().contains('world') || loc.toLowerCase().contains('any');
        final locSnippet = isWorldwide ? '("worldwide" OR "anywhere" OR "global" OR "remote-first")' : '("$loc")';
        const wfhPhrases = '("work from home" OR "remote" OR "wfh" OR "100% remote")';
        const recruiterPhrases = '("hiring" OR "we are hiring" OR "looking for") ("send resume" OR "share CV" OR "email resume" OR "email CV" OR "apply at" OR "drop your resume")';
        return '"$role" $wfhPhrases $locSnippet $recruiterPhrases "@" -site:facebook.com/groups';
      }

      final queryIndia = buildQuery('Flutter Developer', 'India');
      expect(queryIndia, contains('"Flutter Developer"'));
      expect(queryIndia, contains('("India")'));
      expect(queryIndia, contains('("work from home" OR "remote" OR "wfh" OR "100% remote")'));

      final queryWorldwide = buildQuery('DevOps Engineer', 'Worldwide / Anywhere 🌍');
      expect(queryWorldwide, contains('"DevOps Engineer"'));
      expect(queryWorldwide, contains('("worldwide" OR "anywhere" OR "global" OR "remote-first")'));
    });
  });
}

