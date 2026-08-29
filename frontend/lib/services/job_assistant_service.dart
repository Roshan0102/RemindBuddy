import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/job_application.dart';

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
  // AUTO-APPLY SETTINGS & ON-DEMAND TRIGGER
  // ============================================================================

  Future<Map<String, dynamic>> getAutoApplySettings() async {
    final doc = _userDoc;
    if (doc == null) {
      return {
        'enabled': true,
        'targetRoles': ['DevOps Engineer', 'Cloud Engineer', 'Site Reliability Engineer', 'Flutter Developer'],
        'locations': ['Bengaluru', 'India', 'Remote'],
        'maxPerRun': 4,
      };
    }

    final snap = await doc.get();
    if (!snap.exists || snap.data() == null) {
      return {
        'enabled': true,
        'targetRoles': ['DevOps Engineer', 'Cloud Engineer', 'Site Reliability Engineer', 'Flutter Developer'],
        'locations': ['Bengaluru', 'India', 'Remote'],
        'maxPerRun': 4,
      };
    }

    final data = snap.data() as Map<String, dynamic>;
    final settings = Map<String, dynamic>.from(data['autoApplySettings'] ?? {});

    List<String> targetRoles = ['DevOps Engineer', 'Cloud Engineer', 'Site Reliability Engineer', 'Flutter Developer'];
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

    return {
      'enabled': settings['enabled'] ?? true,
      'targetRoles': targetRoles,
      'locations': locations,
      'maxPerRun': settings['maxPerRun'] ?? 4,
    };
  }

  Future<void> saveAutoApplySettings({
    required bool enabled,
    required List<String> targetRoles,
    required List<String> locations,
    int maxPerRun = 4,
  }) async {
    final doc = _userDoc;
    if (doc == null) return;

    await doc.set({
      'autoApplySettings': {
        'enabled': enabled,
        'targetRoles': targetRoles,
        'locations': locations,
        'maxPerRun': maxPerRun,
        'updatedAt': FieldValue.serverTimestamp(),
      }
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>> triggerAutoJobDiscoveryAndApply({
    List<String>? targetRoles,
    List<String>? locations,
    int maxApplications = 4,
  }) async {
    final callable = _functions.httpsCallable('triggerAutoJobDiscoveryAndApply');
    final response = await callable.call({
      'targetRoles': targetRoles,
      'locations': locations,
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

  Future<List<JobApplication>> parseJobPostersWithAI(List<String> imagesBase64, String mode, {String? customPrompt}) async {
    final masterResume = await getMasterResume();

    final callable = _functions.httpsCallable('parseJobPostersWithAI');
    final response = await callable.call({
      'imagesBase64': imagesBase64,
      'mode': mode, // 'single_job' or 'multiple_jobs'
      'resumeBase64': masterResume['base64'],
      'applicantName': 'Roshan J',
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
        generatedSubject: map['generatedSubject'] ?? 'Roshan J - Job Application',
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
  }) async {
    final masterResume = await getMasterResume();

    final callable = _functions.httpsCallable('generateManualJobApplicationWithAI');
    final response = await callable.call({
      'companyName': companyName,
      'jobTitle': jobTitle,
      'companyUrl': companyUrl ?? '',
      'recipientEmails': recipientEmails ?? '',
      'companyNotes': companyNotes ?? '',
      'customPrompt': customPrompt ?? '',
      'resumeBase64': masterResume['base64'],
      'applicantName': 'Roshan J',
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
      generatedSubject: rawJob['generatedSubject'] ?? 'Roshan J - $jobTitle',
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
  }) async {
    final masterResume = await getMasterResume();

    final callable = _functions.httpsCallable('refineCoverLetterWithAI');
    final response = await callable.call({
      'currentSubject': currentSubject,
      'currentCoverLetter': currentCoverLetter,
      'userPrompt': userPrompt,
      'jobTitle': jobTitle,
      'companyName': companyName,
      'resumeBase64': masterResume['base64'],
      'applicantName': 'Roshan J',
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
}
