import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    String cachedName = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      cachedName = (prefs.getString('job_assistant_applicant_name') ?? '').trim();
      if (cachedName.isNotEmpty) return cachedName;
    } catch (_) {}

    final doc = _userDoc;
    if (doc == null) {
      final authName = (FirebaseAuth.instance.currentUser?.displayName ?? '').trim();
      return authName.isNotEmpty ? authName : cachedName;
    }
    try {
      final snap = await doc.get();
      if (snap.exists && snap.data() != null) {
        final data = snap.data() as Map<String, dynamic>;
        final name = (data['applicantName'] ?? data['displayName'] ?? data['name'] ?? '').toString().trim();
        if (name.isNotEmpty) {
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('job_assistant_applicant_name', name);
          } catch (_) {}
          return name;
        }
      }
    } catch (_) {}

    final authName = (FirebaseAuth.instance.currentUser?.displayName ?? '').trim();
    return authName.isNotEmpty ? authName : cachedName;
  }

  Future<void> saveApplicantName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('job_assistant_applicant_name', trimmed);
    } catch (_) {}

    final doc = _userDoc;
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
    String cachedEmail = '';
    String cachedPass = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      cachedEmail = (prefs.getString('job_assistant_user_email') ?? '').trim();
      cachedPass = (prefs.getString('job_assistant_user_app_password') ?? '').trim();
    } catch (_) {}

    final doc = _userDoc;
    if (doc == null) {
      return {
        'email': cachedEmail.isNotEmpty ? cachedEmail : (FirebaseAuth.instance.currentUser?.email ?? ''),
        'appPassword': cachedPass,
      };
    }

    try {
      final snap = await doc.get();
      if (snap.exists && snap.data() != null) {
        final data = snap.data() as Map<String, dynamic>;
        final emailConfig = Map<String, dynamic>.from(
          data['emailConfig'] ?? data['jobEmailConfig'] ?? data['gmailConfig'] ?? {},
        );
        final email = (emailConfig['email'] ?? '').toString().trim();
        final appPassword = (emailConfig['appPassword'] ?? '').toString().trim();

        final resolvedEmail = email.isNotEmpty ? email : cachedEmail;
        final resolvedPass = appPassword.isNotEmpty ? appPassword : cachedPass;

        if (resolvedEmail.isNotEmpty || resolvedPass.isNotEmpty) {
          try {
            final prefs = await SharedPreferences.getInstance();
            if (resolvedEmail.isNotEmpty) await prefs.setString('job_assistant_user_email', resolvedEmail);
            if (resolvedPass.isNotEmpty) await prefs.setString('job_assistant_user_app_password', resolvedPass);
          } catch (_) {}
        }

        return {
          'email': resolvedEmail.isNotEmpty ? resolvedEmail : (FirebaseAuth.instance.currentUser?.email ?? ''),
          'appPassword': resolvedPass,
        };
      }
    } catch (_) {}

    return {
      'email': cachedEmail.isNotEmpty ? cachedEmail : (FirebaseAuth.instance.currentUser?.email ?? ''),
      'appPassword': cachedPass,
    };
  }

  Future<void> saveUserEmailConfig(String email, String appPassword) async {
    final cleanEmail = email.trim();
    final cleanPass = appPassword.trim();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('job_assistant_user_email', cleanEmail);
      await prefs.setString('job_assistant_user_app_password', cleanPass);
    } catch (_) {}

    final doc = _userDoc;
    if (doc == null) return;

    await doc.set({
      'emailConfig': {
        'email': cleanEmail,
        'appPassword': cleanPass,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'jobEmailConfig': {
        'email': cleanEmail,
        'appPassword': cleanPass,
      }
    }, SetOptions(merge: true));
  }

  Future<Map<String, String>> getMasterResume() async {
    String cachedFileName = '';
    String cachedBase64 = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      cachedFileName = (prefs.getString('job_assistant_resume_filename') ?? '').trim();
      cachedBase64 = (prefs.getString('job_assistant_resume_base64') ?? '').trim();
    } catch (_) {}

    final doc = _userDoc;
    if (doc == null) {
      return {'base64': cachedBase64, 'fileName': cachedFileName.isNotEmpty ? cachedFileName : 'Resume.pdf'};
    }

    try {
      final snap = await doc.get();
      if (snap.exists && snap.data() != null) {
        final data = snap.data() as Map<String, dynamic>;
        final resume = Map<String, dynamic>.from(data['masterResume'] ?? data['resume'] ?? {});
        var b64 = (resume['base64'] ?? resume['base64Data'] ?? data['resumeBase64'] ?? '').toString();
        var fName = (resume['fileName'] ?? data['resumeFileName'] ?? '').toString();

        // If root masterResume base64 is empty, check targeted resume profiles subcollection
        if (b64.isEmpty) {
          final profiles = await getResumeProfiles();
          if (profiles.isNotEmpty) {
            final def = profiles.firstWhere((p) => p.isDefault, orElse: () => profiles.first);
            b64 = def.base64;
            fName = def.fileName;
          }
        }

        final resolvedB64 = b64.isNotEmpty ? b64 : cachedBase64;
        final resolvedName = fName.isNotEmpty ? fName : (cachedFileName.isNotEmpty ? cachedFileName : 'Resume.pdf');

        if (resolvedName.isNotEmpty || resolvedB64.isNotEmpty) {
          try {
            final prefs = await SharedPreferences.getInstance();
            if (resolvedName.isNotEmpty) await prefs.setString('job_assistant_resume_filename', resolvedName);
            if (resolvedB64.isNotEmpty) await prefs.setString('job_assistant_resume_base64', resolvedB64);
            await prefs.setBool('job_assistant_has_resume', resolvedB64.isNotEmpty || resolvedName.isNotEmpty);
          } catch (_) {}
        }

        return {
          'base64': resolvedB64,
          'fileName': resolvedName,
        };
      }
    } catch (_) {}

    return {'base64': cachedBase64, 'fileName': cachedFileName.isNotEmpty ? cachedFileName : 'Resume.pdf'};
  }

  Future<void> saveMasterResume(String base64Content, String fileName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('job_assistant_resume_filename', fileName);
      await prefs.setString('job_assistant_resume_base64', base64Content);
      await prefs.setBool('job_assistant_has_resume', true);
    } catch (_) {}

    final doc = _userDoc;
    if (doc == null) return;

    await doc.set({
      'masterResume': {
        'base64': base64Content,
        'base64Data': base64Content,
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
    List<String> cachedRoles = [];
    List<String> cachedLocs = [];
    List<String> cachedExcluded = [];
    int cachedMinExp = 0;
    int cachedMaxExp = 3;
    bool cachedFresher = false;
    bool cachedEnabled = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final rolesStr = prefs.getString('job_assistant_target_roles') ?? '';
      if (rolesStr.isNotEmpty) {
        cachedRoles = rolesStr.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      }
      final locsStr = prefs.getString('job_assistant_locations') ?? '';
      if (locsStr.isNotEmpty) {
        cachedLocs = locsStr.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      }
      cachedExcluded = prefs.getStringList('job_assistant_excluded_companies') ?? [];
      cachedMinExp = prefs.getInt('job_assistant_min_exp') ?? 0;
      cachedMaxExp = prefs.getInt('job_assistant_max_exp') ?? 3;
      cachedFresher = prefs.getBool('job_assistant_is_fresher') ?? (cachedMinExp == 0 && cachedMaxExp == 0);
      cachedEnabled = prefs.getBool('job_assistant_enabled') ?? true;
    } catch (_) {}

    final doc = _userDoc;
    if (doc == null) {
      return {
        'enabled': cachedEnabled,
        'targetRoles': cachedRoles,
        'locations': cachedLocs.isNotEmpty ? cachedLocs : ['Bengaluru', 'India', 'Remote'],
        'excludedCompanies': cachedExcluded,
        'minExpYears': cachedMinExp,
        'maxExpYears': cachedMaxExp,
        'isFresher': cachedFresher,
        'maxPerRun': 6,
      };
    }

    try {
      final snap = await doc.get();
      if (snap.exists && snap.data() != null) {
        final data = snap.data() as Map<String, dynamic>;
        final settings = Map<String, dynamic>.from(data['autoApplySettings'] ?? data['autoApply'] ?? data['jobPreferences'] ?? {});

        List<String> targetRoles = [];
        final rawRoles = settings['targetRoles'] ?? data['targetRoles'] ?? data['techDomains'];
        if (rawRoles is List) {
          targetRoles = List<String>.from(rawRoles);
        } else if (rawRoles is String) {
          targetRoles = rawRoles.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        }
        if (targetRoles.isEmpty && cachedRoles.isNotEmpty) {
          targetRoles = cachedRoles;
        }

        List<String> locations = [];
        final rawLocs = settings['locations'] ?? data['locations'] ?? data['targetLocations'];
        if (rawLocs is List) {
          locations = List<String>.from(rawLocs);
        } else if (rawLocs is String) {
          locations = rawLocs.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        }
        if (locations.isEmpty && cachedLocs.isNotEmpty) {
          locations = cachedLocs;
        }
        if (locations.isEmpty) {
          locations = ['Bengaluru', 'India', 'Remote'];
        }

        List<String> excludedCompanies = [];
        final rawExcluded = settings['excludedCompanies'] ?? data['excludedCompanies'];
        if (rawExcluded is List) {
          excludedCompanies = List<String>.from(rawExcluded);
        } else if (rawExcluded is String) {
          excludedCompanies = rawExcluded.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        }
        if (excludedCompanies.isEmpty && cachedExcluded.isNotEmpty) {
          excludedCompanies = cachedExcluded;
        }

        final minE = settings['minExpYears'] ?? cachedMinExp;
        final maxE = settings['maxExpYears'] ?? cachedMaxExp;
        final isFr = settings['isFresher'] ?? cachedFresher;
        final en = settings['enabled'] ?? cachedEnabled;

        // Sync to SharedPreferences
        try {
          final prefs = await SharedPreferences.getInstance();
          if (targetRoles.isNotEmpty) await prefs.setString('job_assistant_target_roles', targetRoles.join(', '));
          if (locations.isNotEmpty) await prefs.setString('job_assistant_locations', locations.join(', '));
          await prefs.setStringList('job_assistant_excluded_companies', excludedCompanies);
          await prefs.setInt('job_assistant_min_exp', minE is int ? minE : (int.tryParse(minE.toString()) ?? 0));
          await prefs.setInt('job_assistant_max_exp', maxE is int ? maxE : (int.tryParse(maxE.toString()) ?? 3));
          await prefs.setBool('job_assistant_is_fresher', isFr == true);
          await prefs.setBool('job_assistant_enabled', en == true);
        } catch (_) {}

        return {
          'enabled': en,
          'targetRoles': targetRoles,
          'locations': locations,
          'excludedCompanies': excludedCompanies,
          'minExpYears': minE,
          'maxExpYears': maxE,
          'isFresher': isFr,
          'maxPerRun': settings['maxPerRun'] ?? 6,
        };
      }
    } catch (_) {}

    return {
      'enabled': cachedEnabled,
      'targetRoles': cachedRoles,
      'locations': cachedLocs.isNotEmpty ? cachedLocs : ['Bengaluru', 'India', 'Remote'],
      'excludedCompanies': cachedExcluded,
      'minExpYears': cachedMinExp,
      'maxExpYears': cachedMaxExp,
      'isFresher': cachedFresher,
      'maxPerRun': 6,
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
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('job_assistant_target_roles', targetRoles.join(', '));
      await prefs.setString('job_assistant_locations', locations.join(', '));
      await prefs.setStringList('job_assistant_excluded_companies', excludedCompanies);
      await prefs.setInt('job_assistant_min_exp', minExpYears);
      await prefs.setInt('job_assistant_max_exp', maxExpYears);
      await prefs.setBool('job_assistant_is_fresher', isFresher);
      await prefs.setBool('job_assistant_enabled', enabled);
    } catch (_) {}

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

  Future<void> setAutoApplyEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('job_assistant_enabled', enabled);
    } catch (_) {}

    final doc = _userDoc;
    if (doc == null) return;

    await doc.set({
      'autoApplySettings': {
        'enabled': enabled,
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
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('job_assistant_radar_locations', locations);
      await prefs.setStringList('job_assistant_radar_domains', techDomains);
    } catch (_) {}

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
    List<String> cachedLocs = [];
    List<String> cachedDomains = [];
    try {
      final prefs = await SharedPreferences.getInstance();
      cachedLocs = prefs.getStringList('job_assistant_radar_locations') ?? [];
      cachedDomains = prefs.getStringList('job_assistant_radar_domains') ?? [];
    } catch (_) {}

    final doc = _userDoc;
    if (doc == null) {
      return {
        'locations': cachedLocs,
        'techDomains': cachedDomains,
      };
    }

    try {
      final snap = await doc.get();
      if (snap.exists && snap.data() != null) {
        final data = snap.data() as Map<String, dynamic>?;
        final settings = Map<String, dynamic>.from(data?['startupRadarSettings'] ?? data?['startupSettings'] ?? data?['radarSettings'] ?? {});
        List<String> locs = [];
        if (settings['locations'] is List) {
          locs = List<String>.from(settings['locations']);
        }
        if (locs.isEmpty && cachedLocs.isNotEmpty) {
          locs = cachedLocs;
        }

        List<String> domains = [];
        if (settings['techDomains'] is List) {
          domains = List<String>.from(settings['techDomains']);
        }
        if (domains.isEmpty && cachedDomains.isNotEmpty) {
          domains = cachedDomains;
        }

        // If still empty, fallback to autoApplySettings roles and locations!
        if (locs.isEmpty) {
          final autoApplyLocs = data?['autoApplySettings']?['locations'] ?? data?['locations'];
          if (autoApplyLocs is List) locs = List<String>.from(autoApplyLocs);
        }
        if (domains.isEmpty) {
          final autoApplyRoles = data?['autoApplySettings']?['targetRoles'] ?? data?['targetRoles'];
          if (autoApplyRoles is List) domains = List<String>.from(autoApplyRoles);
        }

        // Cache to SharedPreferences
        try {
          final prefs = await SharedPreferences.getInstance();
          if (locs.isNotEmpty) await prefs.setStringList('job_assistant_radar_locations', locs);
          if (domains.isNotEmpty) await prefs.setStringList('job_assistant_radar_domains', domains);
        } catch (_) {}

        return {
          'locations': locs,
          'techDomains': domains,
        };
      }
    } catch (_) {}

    return {
      'locations': cachedLocs,
      'techDomains': cachedDomains,
    };
  }
}
