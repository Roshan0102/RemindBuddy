import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/job_application.dart';
import '../models/networking_lead.dart';
import '../models/resume_profile.dart';

class JobAssistantService {
  static final JobAssistantService _instance = JobAssistantService._internal();
  factory JobAssistantService() => _instance;
  JobAssistantService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference? get _userDoc {
    final uid = _uid;
    if (uid == null) return null;
    return _db.collection('users').doc(uid);
  }

  // ============================================================================
  // USER APPLICANT NAME & PROFILE
  // ============================================================================

  Future<String> getApplicantName() async {
    final doc = _userDoc;
    if (doc == null) {
      return FirebaseAuth.instance.currentUser?.displayName ?? '';
    }
    try {
      final snap = await doc.get();
      if (snap.exists && snap.data() != null) {
        final data = snap.data() as Map<String, dynamic>;
        final name = (data['applicantName'] ?? data['displayName'] ?? '').toString().trim();
        if (name.isNotEmpty) return name;
      }
    } catch (_) {}
    return FirebaseAuth.instance.currentUser?.displayName ?? '';
  }

  Future<void> saveApplicantName(String name) async {
    final doc = _userDoc;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    if (doc != null) {
      await doc.set({
        'applicantName': trimmed,
        'displayName': trimmed,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    try {
      await FirebaseAuth.instance.currentUser?.updateDisplayName(trimmed);
    } catch (_) {}
  }

  // ============================================================================
  // USER EMAIL CONFIG & MASTER RESUME
  // ============================================================================

  Future<Map<String, String>> getUserEmailConfig() async {
    final doc = _userDoc;
    if (doc == null) return {'email': '', 'appPassword': ''};

    final snap = await doc.get();
    if (!snap.exists || snap.data() == null) return {'email': '', 'appPassword': ''};

    final data = snap.data() as Map<String, dynamic>;
    final emailConfig = Map<String, dynamic>.from(data['emailConfig'] ?? {});

    return {
      'email': (emailConfig['email'] ?? '').toString(),
      'appPassword': (emailConfig['appPassword'] ?? '').toString(),
    };
  }

  Future<void> saveUserEmailConfig(String email, String appPassword) async {
    final doc = _userDoc;
    if (doc == null) return;

    await doc.set({
      'emailConfig': {
        'email': email.trim(),
        'appPassword': appPassword.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }
    }, SetOptions(merge: true));
  }

  Future<Map<String, String>> getMasterResume() async {
    final doc = _userDoc;
    if (doc == null) return {'base64': '', 'fileName': ''};

    final snap = await doc.get();
    if (!snap.exists || snap.data() == null) return {'base64': '', 'fileName': ''};

    final data = snap.data() as Map<String, dynamic>;
    final resume = Map<String, dynamic>.from(data['masterResume'] ?? {});

    return {
      'base64': (resume['base64'] ?? '').toString(),
      'fileName': (resume['fileName'] ?? 'Resume.pdf').toString(),
    };
  }

  Future<void> saveMasterResume(String base64Content, String fileName) async {
    final doc = _userDoc;
    if (doc == null) return;

    await doc.set({
      'masterResume': {
        'base64': base64Content,
        'fileName': fileName,
        'updatedAt': FieldValue.serverTimestamp(),
      }
    }, SetOptions(merge: true));
  }

  // ============================================================================
  // MULTI-RESUME PROFILES MANAGEMENT
  // ============================================================================

  Stream<List<ResumeProfile>> getResumeProfilesStream() {
    final doc = _userDoc;
    if (doc == null) return Stream.value([]);

    return doc
        .collection('resume_profiles')
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => ResumeProfile.fromMap(d.data(), d.id)).toList());
  }

  Future<List<ResumeProfile>> getResumeProfiles() async {
    final doc = _userDoc;
    if (doc == null) return [];

    final snap = await doc.collection('resume_profiles').orderBy('updatedAt', descending: true).get();
    return snap.docs.map((d) => ResumeProfile.fromMap(d.data(), d.id)).toList();
  }

  Future<void> saveResumeProfile(ResumeProfile profile) async {
    final doc = _userDoc;
    if (doc == null) return;

    final collection = doc.collection('resume_profiles');
    final ref = profile.id.isNotEmpty ? collection.doc(profile.id) : collection.doc();

    final updated = profile.copyWith(id: ref.id, updatedAt: DateTime.now());

    // If marked default, unset any other defaults
    if (updated.isDefault) {
      final existing = await collection.where('isDefault', isEqualTo: true).get();
      for (final d in existing.docs) {
        if (d.id != ref.id) {
          await d.reference.update({'isDefault': false});
        }
      }
      // Also update masterResume root document for backward compatibility
      await saveMasterResume(updated.base64, updated.fileName);
    }

    await ref.set(updated.toMap(), SetOptions(merge: true));
  }

  Future<void> deleteResumeProfile(String profileId) async {
    final doc = _userDoc;
    if (doc == null) return;

    await doc.collection('resume_profiles').doc(profileId).delete();
  }

  Future<void> setDefaultResumeProfile(String profileId) async {
    final doc = _userDoc;
    if (doc == null) return;

    final collection = doc.collection('resume_profiles');
    final all = await collection.get();
    for (final d in all.docs) {
      final isDef = (d.id == profileId);
      await d.reference.update({'isDefault': isDef});
      if (isDef) {
        final data = d.data();
        await saveMasterResume((data['base64'] ?? '').toString(), (data['fileName'] ?? 'Resume.pdf').toString());
      }
    }
  }

  // ============================================================================
  // AUTO-APPLY SETTINGS & ON-DEMAND TRIGGER
  // ============================================================================

  Future<Map<String, dynamic>> getAutoApplySettings() async {
    final doc = _userDoc;
    if (doc == null) {
      return {
        'enabled': true,
        'targetRoles': <String>[],
        'locations': ['Bengaluru', 'India', 'Remote'],
        'excludedCompanies': <String>[],
        'maxPerRun': 4,
      };
    }

    final snap = await doc.get();
    if (!snap.exists || snap.data() == null) {
      return {
        'enabled': true,
        'targetRoles': <String>[],
        'locations': ['Bengaluru', 'India', 'Remote'],
        'excludedCompanies': <String>[],
        'maxPerRun': 4,
      };
    }

    final data = snap.data() as Map<String, dynamic>;
    final settings = Map<String, dynamic>.from(data['autoApplySettings'] ?? {});

    List<String> targetRoles = [];
    if (settings['targetRoles'] is List) {
      targetRoles = List<String>.from(settings['targetRoles']);
    } else if (settings['targetRoles'] is String) {
      targetRoles = (settings['targetRoles'] as String).split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }

    List<String> locations = ['Bengaluru', 'India', 'Remote'];
    if (settings['locations'] is List) {
      locations = List<String>.from(settings['locations']);
    } else if (settings['locations'] is String) {
      locations = (settings['locations'] as String).split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }

    List<String> excludedCompanies = [];
    if (settings['excludedCompanies'] is List) {
      excludedCompanies = List<String>.from(settings['excludedCompanies']);
    } else if (settings['excludedCompanies'] is String) {
      excludedCompanies = (settings['excludedCompanies'] as String).split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }

    return {
      'enabled': settings['enabled'] ?? true,
      'targetRoles': targetRoles,
      'locations': locations,
      'excludedCompanies': excludedCompanies,
      'minExpYears': settings['minExpYears'] ?? 0,
      'maxExpYears': settings['maxExpYears'] ?? 3,
      'maxPerRun': settings['maxPerRun'] ?? 4,
    };
  }

  Future<void> saveAutoApplySettings({
    required bool enabled,
    required List<String> targetRoles,
    required List<String> locations,
    List<String> excludedCompanies = const [],
    int minExpYears = 0,
    int maxExpYears = 3,
    bool isFresher = false,
    int maxPerRun = 6,
  }) async {
    final doc = _userDoc;
    if (doc == null) return;

    await doc.set({
      'autoApplySettings': {
        'enabled': enabled,
        'targetRoles': targetRoles,
        'locations': locations,
        'excludedCompanies': excludedCompanies,
        'minExpYears': minExpYears,
        'maxExpYears': maxExpYears,
        'isFresher': isFresher,
        'maxPerRun': maxPerRun,
        'updatedAt': FieldValue.serverTimestamp(),
      }
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>> triggerAutoJobDiscoveryAndApply({
    String? applicantName,
    List<String>? targetRoles,
    List<String>? locations,
    List<String>? excludedCompanies,
    int minExpYears = 0,
    int maxExpYears = 3,
    int maxApplications = 4,
  }) async {
    final resolvedName = (applicantName != null && applicantName.trim().isNotEmpty)
        ? applicantName.trim()
        : await getApplicantName();

    final callable = _functions.httpsCallable(
      'triggerAutoJobDiscoveryAndApply',
      options: HttpsCallableOptions(timeout: const Duration(minutes: 5)),
    );
    final response = await callable.call({
      'applicantName': resolvedName,
      'targetRoles': targetRoles,
      'locations': locations,
      'excludedCompanies': excludedCompanies,
      'minExpYears': minExpYears,
      'maxExpYears': maxExpYears,
      'maxApplications': maxApplications,
    });

    final resData = response.data;
    if (resData == null || resData['success'] != true) {
      throw Exception(resData?['message'] ?? 'Failed to trigger automated job discovery & outreach.');
    }

    return Map<String, dynamic>.from(resData);
  }

  // ============================================================================
  // JOB APPLICATIONS CRUD
  // ============================================================================

  Stream<List<JobApplication>> getJobApplicationsStream() {
    final doc = _userDoc;
    if (doc == null) return Stream.value([]);

    return doc
        .collection('job_applications')
        .orderBy('appliedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => JobApplication.fromMap(d.data(), d.id)).toList());
  }

  Future<void> saveJobApplication(JobApplication app) async {
    final doc = _userDoc;
    if (doc == null) return;

    final ref = app.id.isNotEmpty
        ? doc.collection('job_applications').doc(app.id)
        : doc.collection('job_applications').doc();

    final newApp = JobApplication(
      id: ref.id,
      jobTitle: app.jobTitle,
      companyName: app.companyName,
      recipientEmail: app.recipientEmail,
      extractedSkills: app.extractedSkills,
      generatedSubject: app.generatedSubject,
      generatedCoverLetter: app.generatedCoverLetter,
      status: app.status,
      appliedAt: app.appliedAt,
      posterImageUrls: app.posterImageUrls,
      errorMessage: app.errorMessage,
      isAutoApplied: app.isAutoApplied,
      location: app.location,
      experienceRequired: app.experienceRequired,
      sourcePlatform: app.sourcePlatform,
      modelUsed: app.modelUsed,
      responseType: app.responseType,
      replyReceivedAt: app.replyReceivedAt,
      replySender: app.replySender,
      replySubject: app.replySubject,
      replySnippet: app.replySnippet,
      replyBodyPreview: app.replyBodyPreview,
      actionRequired: app.actionRequired,
      resumeProfileName: app.resumeProfileName,
    );

    await ref.set(newApp.toMap(), SetOptions(merge: true));
  }

  Future<void> deleteJobApplication(String appId) async {
    final doc = _userDoc;
    if (doc == null) return;

    await doc.collection('job_applications').doc(appId).delete();
  }

  // ============================================================================
  // AI PARSING & EMAIL DISPATCH
  // ============================================================================

  Future<List<JobApplication>> parseJobPostersWithAI(List<String> imagesBase64, String mode, {String? customPrompt, String? applicantName}) async {
    final masterResume = await getMasterResume();
    final resolvedName = (applicantName != null && applicantName.trim().isNotEmpty)
        ? applicantName.trim()
        : await getApplicantName();

    final callable = _functions.httpsCallable('parseJobPostersWithAI');
    final response = await callable.call({
      'imagesBase64': imagesBase64,
      'mode': mode, // 'single_job' or 'multiple_jobs'
      'resumeBase64': masterResume['base64'],
      'applicantName': resolvedName.isNotEmpty ? resolvedName : 'Candidate',
      'customPrompt': customPrompt ?? '',
    });

    final resData = response.data;
    if (resData == null || resData['success'] != true) {
      throw Exception('Failed to analyze job poster(s) with AI.');
    }

    final rawJobs = resData['jobs'] as List? ?? [];
    final List<JobApplication> parsedJobs = [];

    for (final raw in rawJobs) {
      final map = Map<String, dynamic>.from(raw);
      parsedJobs.add(JobApplication(
        id: '',
        jobTitle: map['jobTitle'] ?? 'Job Position',
        companyName: map['companyName'] ?? 'Company',
        recipientEmail: map['recipientEmail'] ?? '',
        extractedSkills: List<String>.from(map['extractedSkills'] ?? []),
        generatedSubject: map['generatedSubject'] ?? '${resolvedName.isNotEmpty ? resolvedName : "Candidate"} - Job Application',
        generatedCoverLetter: map['generatedCoverLetter'] ?? '',
        status: 'extracted',
        appliedAt: DateTime.now(),
      ));
    }

    return parsedJobs;
  }

  Future<JobApplication> generateManualJobApplicationWithAI({
    required String companyName,
    required String jobTitle,
    String? companyUrl,
    String? recipientEmails,
    String? companyNotes,
    String? customPrompt,
    String? applicantName,
  }) async {
    final masterResume = await getMasterResume();
    final resolvedName = (applicantName != null && applicantName.trim().isNotEmpty)
        ? applicantName.trim()
        : await getApplicantName();

    final callable = _functions.httpsCallable('generateManualJobApplicationWithAI');
    final response = await callable.call({
      'companyName': companyName,
      'jobTitle': jobTitle,
      'companyUrl': companyUrl ?? '',
      'recipientEmails': recipientEmails ?? '',
      'companyNotes': companyNotes ?? '',
      'customPrompt': customPrompt ?? '',
      'resumeBase64': masterResume['base64'],
      'applicantName': resolvedName.isNotEmpty ? resolvedName : 'Candidate',
    });

    final resData = response.data;
    if (resData == null || resData['success'] != true) {
      throw Exception('Failed to generate manual job application with AI.');
    }

    final rawJob = Map<String, dynamic>.from(resData['job'] ?? {});
    return JobApplication(
      id: '',
      jobTitle: rawJob['jobTitle'] ?? jobTitle,
      companyName: rawJob['companyName'] ?? companyName,
      recipientEmail: rawJob['recipientEmail'] ?? recipientEmails ?? '',
      extractedSkills: List<String>.from(rawJob['extractedSkills'] ?? []),
      generatedSubject: rawJob['generatedSubject'] ?? '${resolvedName.isNotEmpty ? resolvedName : "Candidate"} - $jobTitle',
      generatedCoverLetter: rawJob['generatedCoverLetter'] ?? '',
      status: 'extracted',
      appliedAt: DateTime.now(),
    );
  }

  Future<Map<String, String>> refineCoverLetterWithAI({
    required String currentSubject,
    required String currentCoverLetter,
    required String userPrompt,
    required String jobTitle,
    required String companyName,
    String? applicantName,
  }) async {
    final masterResume = await getMasterResume();
    final resolvedName = (applicantName != null && applicantName.trim().isNotEmpty)
        ? applicantName.trim()
        : await getApplicantName();

    final callable = _functions.httpsCallable('refineCoverLetterWithAI');
    final response = await callable.call({
      'currentSubject': currentSubject,
      'currentCoverLetter': currentCoverLetter,
      'userPrompt': userPrompt,
      'jobTitle': jobTitle,
      'companyName': companyName,
      'resumeBase64': masterResume['base64'],
      'applicantName': resolvedName.isNotEmpty ? resolvedName : 'Candidate',
    });

    final resData = response.data;
    if (resData == null || resData['success'] != true) {
      throw Exception('Failed to refine cover letter with AI.');
    }

    return {
      'generatedSubject': (resData['generatedSubject'] ?? currentSubject).toString(),
      'generatedCoverLetter': (resData['generatedCoverLetter'] ?? currentCoverLetter).toString(),
    };
  }

  Future<void> sendJobApplicationEmail(JobApplication app) async {
    final masterResume = await getMasterResume();

    final callable = _functions.httpsCallable('sendJobApplicationEmail');
    final response = await callable.call({
      'recipientEmail': app.recipientEmail,
      'subject': app.generatedSubject,
      'body': app.generatedCoverLetter,
      'resumeBase64': masterResume['base64'],
      'resumeFileName': masterResume['fileName'],
    });

    final resData = response.data;
    if (resData == null || resData['success'] != true) {
      throw Exception('Failed to send application email.');
    }

    // Mark application as sent in Firestore
    await saveJobApplication(JobApplication(
      id: app.id,
      jobTitle: app.jobTitle,
      companyName: app.companyName,
      recipientEmail: app.recipientEmail,
      extractedSkills: app.extractedSkills,
      generatedSubject: app.generatedSubject,
      generatedCoverLetter: app.generatedCoverLetter,
      status: 'sent',
      appliedAt: DateTime.now(),
      posterImageUrls: app.posterImageUrls,
    ));
  }

  // ============================================================================
  // RECRUITER REPLY TRACKER
  // ============================================================================

  Future<Map<String, dynamic>> checkJobRepliesNow() async {
    final callable = _functions.httpsCallable(
      'checkJobRepliesCallable',
      options: HttpsCallableOptions(timeout: const Duration(minutes: 3)),
    );
    final response = await callable.call();
    final resData = response.data;
    if (resData == null || resData['success'] != true) {
      throw Exception(resData?['message'] ?? 'Failed to check recruiter replies.');
    }
    return Map<String, dynamic>.from(resData);
  }

  // ============================================================================
  // COLD OUTREACH & NETWORKING LEADS
  // ============================================================================

  Stream<List<NetworkingLead>> getNetworkingLeadsStream() {
    final doc = _userDoc;
    if (doc == null) return Stream.value([]);

    return doc
        .collection('networking_leads')
        .orderBy('discoveredAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => NetworkingLead.fromMap(d.data(), d.id)).toList());
  }

  Future<void> updateNetworkingLeadStatus(String leadId, String newStatus) async {
    final doc = _userDoc;
    if (doc == null) return;

    await doc.collection('networking_leads').doc(leadId).update({
      'status': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteNetworkingLead(String leadId) async {
    final doc = _userDoc;
    if (doc == null) return;

    await doc.collection('networking_leads').doc(leadId).delete();
  }

  Future<void> dismissReply(String id, bool isStartupLead) async {
    final doc = _userDoc;
    if (doc == null) return;

    final col = isStartupLead ? 'networking_leads' : 'job_applications';
    await doc.collection(col).doc(id).update({
      'replyDismissed': true,
      'isReplyDismissed': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteReply(String id, bool isStartupLead) async {
    final doc = _userDoc;
    if (doc == null) return;

    final col = isStartupLead ? 'networking_leads' : 'job_applications';
    if (isStartupLead) {
      await doc.collection(col).doc(id).update({
        'status': 'email_sent',
        'replyDismissed': true,
        'isReplyDismissed': true,
        'responseType': FieldValue.delete(),
        'replyReceivedAt': FieldValue.delete(),
        'replySender': FieldValue.delete(),
        'replySubject': FieldValue.delete(),
        'replySnippet': FieldValue.delete(),
        'replyBodyPreview': FieldValue.delete(),
        'actionRequired': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await doc.collection(col).doc(id).update({
        'status': 'sent',
        'replyDismissed': true,
        'isReplyDismissed': true,
        'responseType': FieldValue.delete(),
        'replyReceivedAt': FieldValue.delete(),
        'replySender': FieldValue.delete(),
        'replySubject': FieldValue.delete(),
        'replySnippet': FieldValue.delete(),
        'replyBodyPreview': FieldValue.delete(),
        'actionRequired': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<Map<String, dynamic>> triggerNetworkingDiscovery({
    String? applicantName,
    List<String>? targetRoles,
    List<String>? targetLocations,
  }) async {
    final resolvedName = (applicantName != null && applicantName.trim().isNotEmpty)
        ? applicantName.trim()
        : await getApplicantName();

    final callable = _functions.httpsCallable(
      'triggerNetworkingDiscovery',
      options: HttpsCallableOptions(timeout: const Duration(minutes: 3)),
    );
    final response = await callable.call({
      'applicantName': resolvedName,
      if (targetRoles != null && targetRoles.isNotEmpty) 'targetRoles': targetRoles,
      if (targetLocations != null && targetLocations.isNotEmpty) 'targetLocations': targetLocations,
    });
    final resData = response.data;
    if (resData == null || resData['success'] != true) {
      throw Exception(resData?['message'] ?? 'Failed to discover networking leads.');
    }
    return Map<String, dynamic>.from(resData);
  }

  Future<void> saveStartupRadarSettings({
    required List<String> locations,
    required List<String> techDomains,
  }) async {
    final doc = _userDoc;
    if (doc == null) return;

    await doc.set({
      'startupRadarSettings': {
        'locations': locations,
        'techDomains': techDomains,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>> getStartupRadarSettings() async {
    final doc = _userDoc;
    if (doc == null) return {};
    final snap = await doc.get();
    if (!snap.exists || snap.data() == null) return {};
    final data = snap.data() as Map<String, dynamic>?;
    return Map<String, dynamic>.from(data?['startupRadarSettings'] ?? {});
  }
}
