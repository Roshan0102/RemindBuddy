import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../models/job_application.dart';
import '../models/networking_lead.dart';
import '../models/resume_profile.dart';
import '../models/career_portal_job.dart';
import '../services/job_assistant_service.dart';
import '../services/app_file_picker/app_file_picker.dart';
import '../services/url_launcher_helper/url_launcher_helper.dart';
import 'ai_keys_settings_screen.dart';
import 'job_replies_screen.dart';
import 'feature_logs_screen.dart';
import '../services/notification_service.dart';
import '../services/web_clipboard_drag/web_clipboard_drag.dart';

class JobAssistantScreen extends StatefulWidget {
  final int? initialFeatureIndex;
  static final ValueNotifier<int?> selectedFeatureIndexNotifier = ValueNotifier<int?>(null);

  const JobAssistantScreen({super.key, this.initialFeatureIndex});

  @override
  State<JobAssistantScreen> createState() => _JobAssistantScreenState();
}

class _JobAssistantScreenState extends State<JobAssistantScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final JobAssistantService _service = JobAssistantService();

  int? _selectedFeatureIndex;

  // Career Portals State (<48h)
  bool _isDiscoveringPortals = false;
  String _portalFilter = 'all';
  String _portalSearchQuery = '';
  final TextEditingController _portalRoleController = TextEditingController();
  final TextEditingController _portalSearchController = TextEditingController();

  // State
  String _uploadMode = 'single_job'; // 'single_job' or 'multiple_jobs'
  final List<XFile> _selectedImageFiles = [];
  final List<String> _selectedImagesBase64 = [];
  bool _isAnalyzing = false;
  List<JobApplication> _extractedJobs = [];
  bool _autoSendInBackground = false;

  // Screenshot Custom Prompt
  final TextEditingController _customScreenshotPromptController = TextEditingController();

  // Manual Job Application Entry State & Controllers
  final TextEditingController _manualCompanyNameController = TextEditingController();
  final TextEditingController _manualJobTitleController = TextEditingController();
  final TextEditingController _manualCompanyUrlController = TextEditingController();
  final TextEditingController _manualRecipientEmailsController = TextEditingController();
  final TextEditingController _manualCompanyNotesController = TextEditingController();
  final TextEditingController _manualCustomPromptController = TextEditingController();
  bool _isGeneratingManual = false;

  // Controllers & AI Refinement state per job card
  final Map<int, TextEditingController> _emailControllers = {};
  final Map<int, TextEditingController> _subjectControllers = {};
  final Map<int, TextEditingController> _bodyControllers = {};
  final Map<int, TextEditingController> _refinePromptControllers = {};
  final Map<int, bool> _refiningMap = {};
  final ScrollController _newAppScrollController = ScrollController();
  final ScrollController _historyScrollController = ScrollController();

  TextEditingController _getController(Map<int, TextEditingController> map, int index, String initialText) {
    if (!map.containsKey(index)) {
      map[index] = TextEditingController(text: initialText);
    }
    return map[index]!;
  }

  // Resume & Email Config
  String _resumeFileName = '';
  bool _hasResume = false;
  String _userEmail = '';
  String _userAppPassword = '';

  // Multi-Resume Profiles (DevOps vs Flutter vs Cloud)
  List<ResumeProfile> _resumeProfiles = [];
  StreamSubscription? _profilesSub;

  // Auto-Apply Agent State & Excluded Companies
  final TextEditingController _applicantNameController = TextEditingController();
  bool _autoApplyEnabled = true;
  final TextEditingController _targetRolesController = TextEditingController();
  final TextEditingController _locationsController = TextEditingController();
  final TextEditingController _minExpController = TextEditingController(text: '0');
  final TextEditingController _maxExpController = TextEditingController(text: '3');
  bool _isFresher = false;
  List<String> _excludedCompanies = [];
  final TextEditingController _excludeCompanyController = TextEditingController();
  bool _isSavingAutoSettings = false;
  bool _isRunningAutoApply = false;
  String _autoApplyStatusMessage = '';
  final ScrollController _autoAppScrollController = ScrollController();

  // Cached Stream References (Prevent continuous resubscriptions & blinking)
  late Stream<List<JobApplication>> _applicationsStream;
  late Stream<List<NetworkingLead>> _networkingLeadsStream;

  // Execution & Application Timestamps
  DateTime? _jobsLastRan;
  DateTime? _jobsLastApplied;
  StreamSubscription? _userDocSub;
  StreamSubscription? _appsSub;

  // History Tab Filter
  String _historyFilter = 'all'; // 'all', 'replies'

  // Monthly Calendar & Pagination State for Tabs
  DateTime _autoApplyMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  int _autoApplyPage = 1;

  DateTime _networkingMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  int _networkingPage = 1;

  DateTime _historyMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  int _historyPage = 1;

  // Startup Radar & Cold Outreach State
  bool _isDiscoveringLeaders = false;
  final String _networkingCategoryFilter = 'all'; // 'all', 'founder', 'engineering_manager', 'talent_acquisition'
  String _networkingStatusFilter = 'pending'; // Default 'pending' to show pending outreach by default
  final ScrollController _networkingScrollController = ScrollController();
  List<String> _radarLocations = [];
  List<String> _radarTechDomains = [];
  final TextEditingController _newRadarLocController = TextEditingController();
  final TextEditingController _newRadarDomainController = TextEditingController();
  bool _isSavingRadarSettings = false;

  // LinkedIn Auto-Apply (Apify Real-Time Recruiter Posts) State
  bool _isLinkedInAutoApplyModuleEnabled = false;
  bool _isRunningLinkedInAutoApply = false;
  String _linkedInAutoApplyStatusMessage = '';
  DateTime? _linkedInLastRan;
  DateTime? _linkedInLastApplied;
  DateTime _linkedInMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  int _linkedInPage = 1;
  final ScrollController _linkedInScrollController = ScrollController();
  final TextEditingController _apifyToken1Controller = TextEditingController();
  final TextEditingController _apifyToken2Controller = TextEditingController();
  final TextEditingController _apifyToken3Controller = TextEditingController();
  final TextEditingController _linkedInRolesController = TextEditingController(text: 'DevOps Engineer, Cloud Engineer, Site Reliability Engineer');
  final TextEditingController _linkedInMinExpController = TextEditingController(text: '1');
  final TextEditingController _linkedInMaxExpController = TextEditingController(text: '3');
  bool _linkedInAutoApplyEnabled = true;

  @override
  void initState() {
    super.initState();
    _selectedFeatureIndex = widget.initialFeatureIndex ?? JobAssistantScreen.selectedFeatureIndexNotifier.value;
    JobAssistantScreen.selectedFeatureIndexNotifier.addListener(_onFeatureIndexNotified);
    _service.initLocalCache().then((_) {
      if (mounted) setState(() {});
    });
    _applicationsStream = _service.getJobApplicationsStream();
    _networkingLeadsStream = _service.getNetworkingLeadsStream();
    _tabController = TabController(length: 6, vsync: this);
    _loadUserConfig();
    _setupTimestampsListeners();
    _setupResumeProfilesListener();
    _setupPasteAndDropListener();
  }

  void _onFeatureIndexNotified() {
    final newIdx = JobAssistantScreen.selectedFeatureIndexNotifier.value;
    if (newIdx != null && mounted) {
      setState(() {
        _selectedFeatureIndex = newIdx;
      });
      JobAssistantScreen.selectedFeatureIndexNotifier.value = null;
    }
  }

  void _setupResumeProfilesListener() {
    _profilesSub = _service.getResumeProfilesStream().listen((profiles) {
      if (mounted) {
        setState(() {
          _resumeProfiles = profiles;
          if (profiles.isNotEmpty) {
            _hasResume = true;
            final defProfile = profiles.firstWhere((p) => p.isDefault, orElse: () => profiles.first);
            if (_resumeFileName.isEmpty || defProfile.isDefault) {
              _resumeFileName = defProfile.fileName;
            }
          }
        });
      }
    });
  }

  void _setupTimestampsListeners() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _userDocSub = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots()
          .listen((snap) {
        if (!snap.exists || snap.data() == null) return;
        final data = snap.data()!;
        final lastRan = data['jobsLastRan'] ?? data['autoApplyLastRan'] ?? data['autoApplySettings']?['lastRan'];
        final lastApplied = data['jobsLastApplied'] ?? data['autoApplyLastApplied'];

        DateTime? parsedRan;
        if (lastRan is Timestamp) {
          parsedRan = lastRan.toDate();
        } else if (lastRan is String) {
          parsedRan = DateTime.tryParse(lastRan);
        }

        DateTime? parsedApplied;
        if (lastApplied is Timestamp) {
          parsedApplied = lastApplied.toDate();
        } else if (lastApplied is String) {
          parsedApplied = DateTime.tryParse(lastApplied);
        }

        // Live real-time config extraction to ensure UI is never empty
        final applicantName = (data['applicantName'] ?? data['displayName'] ?? data['name'] ?? '').toString().trim();
        final emailCfg = Map<String, dynamic>.from(data['emailConfig'] ?? data['jobEmailConfig'] ?? data['gmailConfig'] ?? {});
        final email = (emailCfg['email'] ?? '').toString().trim();
        final pass = (emailCfg['appPassword'] ?? '').toString().trim();

        final resumeData = Map<String, dynamic>.from(data['masterResume'] ?? data['resume'] ?? {});
        final resumeBase64 = (resumeData['base64'] ?? resumeData['base64Data'] ?? data['resumeBase64'] ?? '').toString();
        final resumeName = (resumeData['fileName'] ?? data['resumeFileName'] ?? '').toString();

        final autoSettings = Map<String, dynamic>.from(data['autoApplySettings'] ?? data['autoApply'] ?? data['jobPreferences'] ?? {});
        List<String> liveRoles = [];
        final rawRoles = autoSettings['targetRoles'] ?? data['targetRoles'] ?? data['techDomains'];
        if (rawRoles is List) {
          liveRoles = List<String>.from(rawRoles);
        } else if (rawRoles is String) {
          liveRoles = rawRoles.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        }

        List<String> liveLocs = [];
        final rawLocs = autoSettings['locations'] ?? data['locations'] ?? data['targetLocations'];
        if (rawLocs is List) {
          liveLocs = List<String>.from(rawLocs);
        } else if (rawLocs is String) {
          liveLocs = rawLocs.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        }

        final radarSettings = Map<String, dynamic>.from(data['startupRadarSettings'] ?? data['startupSettings'] ?? data['radarSettings'] ?? {});
        final liveRadarLocs = List<String>.from(radarSettings['locations'] ?? []);
        final liveRadarTechs = List<String>.from(radarSettings['techDomains'] ?? []);

        if (mounted) {
          final bool ranChanged = parsedRan != null && parsedRan != _jobsLastRan;
          final bool appliedChanged = parsedApplied != null && parsedApplied != _jobsLastApplied;

          setState(() {
            if (ranChanged) _jobsLastRan = parsedRan;
            if (appliedChanged) _jobsLastApplied = parsedApplied;

            if (applicantName.isNotEmpty && _applicantNameController.text.trim().isEmpty) {
              _applicantNameController.text = applicantName;
            }
            if (email.isNotEmpty) {
              _userEmail = email;
            }
            if (pass.isNotEmpty) {
              _userAppPassword = pass;
            }
            if (resumeName.isNotEmpty && _resumeFileName.isEmpty) {
              _resumeFileName = resumeName;
            }
            if (resumeBase64.isNotEmpty || resumeName.isNotEmpty) {
              _hasResume = true;
            }
            if (liveRoles.isNotEmpty && _targetRolesController.text.trim().isEmpty) {
              _targetRolesController.text = liveRoles.join(', ');
            }
            if (liveLocs.isNotEmpty && _locationsController.text.trim().isEmpty) {
              _locationsController.text = liveLocs.join(', ');
            }
            if (liveRadarLocs.isNotEmpty && _radarLocations.isEmpty) {
              _radarLocations = liveRadarLocs;
            } else if (_radarLocations.isEmpty && liveLocs.isNotEmpty) {
              _radarLocations = List.from(liveLocs);
            }
            if (liveRadarTechs.isNotEmpty && _radarTechDomains.isEmpty) {
              _radarTechDomains = liveRadarTechs;
            } else if (_radarTechDomains.isEmpty && liveRoles.isNotEmpty) {
              _radarTechDomains = List.from(liveRoles);
            }
            if (autoSettings.containsKey('enabled')) {
              _autoApplyEnabled = autoSettings['enabled'] == true;
            }

            final enabledMods = List<String>.from(data['enabledModules'] ?? []);
            _isLinkedInAutoApplyModuleEnabled = enabledMods.contains('linkedin_auto_apply');

            final lRan = data['linkedinAutoApplyLastRan'];
            if (lRan is Timestamp) {
              _linkedInLastRan = lRan.toDate();
            } else if (lRan is String) {
              _linkedInLastRan = DateTime.tryParse(lRan);
            }

            final lApplied = data['linkedinAutoApplyLastApplied'];
            if (lApplied is Timestamp) {
              _linkedInLastApplied = lApplied.toDate();
            } else if (lApplied is String) {
              _linkedInLastApplied = DateTime.tryParse(lApplied);
            }

            final lSettings = Map<String, dynamic>.from(data['linkedinAutoApplySettings'] ?? {});
            if (lSettings.isNotEmpty) {
              if (_apifyToken1Controller.text.isEmpty && lSettings['apifyToken1'] != null) {
                _apifyToken1Controller.text = lSettings['apifyToken1'];
              }
              if (_apifyToken2Controller.text.isEmpty && lSettings['apifyToken2'] != null) {
                _apifyToken2Controller.text = lSettings['apifyToken2'];
              }
              if (_apifyToken3Controller.text.isEmpty && lSettings['apifyToken3'] != null) {
                _apifyToken3Controller.text = lSettings['apifyToken3'];
              }
              if (lSettings['enabled'] != null) {
                _linkedInAutoApplyEnabled = lSettings['enabled'] == true;
              }
            }
          });
        }
      });
    }

    _appsSub = _applicationsStream.listen((apps) {
      final sentApps = apps.where((a) => a.status == 'sent' || a.isAutoApplied).toList();
      if (sentApps.isNotEmpty && mounted) {
        final latest = sentApps.first.appliedAt;
        if (_jobsLastApplied == null || latest.isAfter(_jobsLastApplied!)) {
          setState(() {
            _jobsLastApplied = latest;
          });
        }
      }
    });
  }

  String _formatRelativeTimestamp(DateTime? dt, {bool isLastRun = false}) {
    if (dt == null) return 'Never';
    return DateFormat('MMM d, h:mm a').format(dt);
  }

  @override
  void dispose() {
    JobAssistantScreen.selectedFeatureIndexNotifier.removeListener(_onFeatureIndexNotified);
    _portalRoleController.dispose();
    _portalSearchController.dispose();
    _userDocSub?.cancel();
    _appsSub?.cancel();
    _tabController.dispose();
    _autoAppScrollController.dispose();
    _networkingScrollController.dispose();
    _newRadarLocController.dispose();
    _newRadarDomainController.dispose();
    _newAppScrollController.dispose();
    _historyScrollController.dispose();
    _applicantNameController.dispose();
    _targetRolesController.dispose();
    _locationsController.dispose();
    _minExpController.dispose();
    _maxExpController.dispose();
    _excludeCompanyController.dispose();
    _profilesSub?.cancel();
    _customScreenshotPromptController.dispose();
    _manualCompanyNameController.dispose();
    _manualJobTitleController.dispose();
    _manualCompanyUrlController.dispose();
    _manualRecipientEmailsController.dispose();
    _manualCompanyNotesController.dispose();
    _manualCustomPromptController.dispose();
    _linkedInScrollController.dispose();
    _apifyToken1Controller.dispose();
    _apifyToken2Controller.dispose();
    _apifyToken3Controller.dispose();
    _linkedInRolesController.dispose();
    _linkedInMinExpController.dispose();
    _linkedInMaxExpController.dispose();
    for (var c in _emailControllers.values) { c.dispose(); }
    for (var c in _subjectControllers.values) { c.dispose(); }
    for (var c in _bodyControllers.values) { c.dispose(); }
    for (var c in _refinePromptControllers.values) { c.dispose(); }
    WebClipboardDrag.disposeListeners();
    super.dispose();
  }

  void _setupPasteAndDropListener() {
    WebClipboardDrag.initListeners(
      onImageReceived: (bytes, name) {
        if (!mounted) return;
        final b64 = base64Encode(bytes);
        setState(() {
          _selectedImageFiles.add(XFile.fromData(bytes, name: name));
          _selectedImagesBase64.add(b64);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📸 Added image: $name (${(bytes.length / 1024).toStringAsFixed(1)} KB)'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.indigo,
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      isActive: () => mounted && _tabController.index == 3,
    );
  }

  Future<void> _pasteImageFromClipboard() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📋 Right-click any image in LinkedIn -> "Copy Image" and press Ctrl+V (or drop here)!'),
          duration: Duration(seconds: 4),
          backgroundColor: Colors.indigo,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Clipboard paste active. Copy an image and press Ctrl+V.'),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _loadUserConfig() async {
    // 1. FAST LOCAL SYNC: load immediately from SharedPreferences so fields are never blank after app update
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = FirebaseAuth.instance.currentUser?.uid;
      String userKey(String key) => uid != null ? '${uid}_$key' : key;

      final localNameCleared = prefs.getBool(userKey('job_assistant_applicant_name_explicitly_cleared')) ?? false;
      final localName = localNameCleared ? '' : (prefs.getString(userKey('job_assistant_applicant_name')) ?? '');
      final localRoles = prefs.getString(userKey('job_assistant_target_roles')) ?? '';
      final localLocs = prefs.getString(userKey('job_assistant_locations')) ?? '';
      final localEmailCleared = prefs.getBool(userKey('job_assistant_user_email_explicitly_cleared')) ?? false;
      final localEmail = localEmailCleared ? '' : (prefs.getString(userKey('job_assistant_user_email')) ?? '');
      final localPass = prefs.getString(userKey('job_assistant_user_app_password')) ?? '';
      final localResumeFileName = prefs.getString(userKey('job_assistant_resume_filename')) ?? '';
      final localHasResume = prefs.getBool(userKey('job_assistant_has_resume')) ?? false;
      final localEnabled = prefs.getBool(userKey('job_assistant_enabled')) ?? true;
      final localMinE = prefs.getInt(userKey('job_assistant_min_exp')) ?? 0;
      final localMaxE = prefs.getInt(userKey('job_assistant_max_exp')) ?? 3;
      final localIsFresher = prefs.getBool(userKey('job_assistant_is_fresher')) ?? (localMinE == 0 && localMaxE == 0);
      final localExcluded = prefs.getStringList(userKey('job_assistant_excluded_companies')) ?? [];
      final localRadarLocs = prefs.getStringList(userKey('job_assistant_radar_locations')) ?? [];
      final localRadarTechs = prefs.getStringList(userKey('job_assistant_radar_domains')) ?? [];

      if (mounted) {
        setState(() {
          if (localNameCleared) {
            _applicantNameController.text = '';
          } else if (localName.isNotEmpty) {
            _applicantNameController.text = localName;
          }
          if (localRoles.isNotEmpty) {
            _targetRolesController.text = localRoles;
          }
          if (localLocs.isNotEmpty) {
            _locationsController.text = localLocs;
          }
          if (localEmailCleared) {
            _userEmail = '';
          } else if (localEmail.isNotEmpty) {
            _userEmail = localEmail;
          }
          _userAppPassword = localPass;
          _resumeFileName = localResumeFileName;
          _hasResume = localHasResume && localResumeFileName.isNotEmpty;
          _autoApplyEnabled = localEnabled;
          _isFresher = localIsFresher;
          _minExpController.text = localMinE.toString();
          _maxExpController.text = localMaxE.toString();
          if (localExcluded.isNotEmpty) {
            _excludedCompanies = localExcluded;
          }
          if (localRadarLocs.isNotEmpty) {
            _radarLocations = localRadarLocs;
          }
          if (localRadarTechs.isNotEmpty) {
            _radarTechDomains = localRadarTechs;
          }
        });
      }
    } catch (_) {}

    // 2. REMOTE SYNC: Fetch complete profile from Service / Firestore
    final applicantName = await _service.getApplicantName();
    final emailConfig = await _service.getUserEmailConfig();
    final masterResume = await _service.getMasterResume();
    final autoSettings = await _service.getAutoApplySettings();
    final targetRoles = List<String>.from(autoSettings['targetRoles'] ?? []);
    final locations = List<String>.from(autoSettings['locations'] ?? []);
    final excluded = List<String>.from(autoSettings['excludedCompanies'] ?? []);

    if (mounted) {
      setState(() {
        _applicantNameController.text = applicantName;
        _userEmail = emailConfig['email'] ?? '';
        _userAppPassword = emailConfig['appPassword'] ?? '';
        final resumeFile = masterResume['fileName'] ?? '';
        final hasResumeContent = (masterResume['base64'] ?? '').isNotEmpty;
        if (hasResumeContent && resumeFile.isNotEmpty) {
          _resumeFileName = resumeFile;
          _hasResume = true;
        } else if (_resumeProfiles.isNotEmpty) {
          _resumeFileName = _resumeProfiles.first.fileName;
          _hasResume = true;
        } else {
          _resumeFileName = '';
          _hasResume = false;
        }
        _autoApplyEnabled = autoSettings['enabled'] ?? _autoApplyEnabled;
        if (excluded.isNotEmpty) {
          _excludedCompanies = excluded;
        }
        final minE = autoSettings['minExpYears'] ?? 0;
        final maxE = autoSettings['maxExpYears'] ?? 3;
        _isFresher = autoSettings['isFresher'] == true || (minE == 0 && maxE == 0);
        _minExpController.text = minE.toString();
        _maxExpController.text = maxE.toString();
        if (targetRoles.isNotEmpty) {
          _targetRolesController.text = targetRoles.join(', ');
        }
        if (locations.isNotEmpty) {
          _locationsController.text = locations.join(', ');
        }
      });

      final radarSettings = await _service.getStartupRadarSettings();
      final radarLocs = List<String>.from(radarSettings['locations'] ?? []);
      final radarTechs = List<String>.from(radarSettings['techDomains'] ?? []);
      if (mounted) {
        setState(() {
          if (radarLocs.isNotEmpty) {
            _radarLocations = radarLocs;
          } else if (_radarLocations.isEmpty && locations.isNotEmpty) {
            _radarLocations = List.from(locations);
          }
          if (radarTechs.isNotEmpty) {
            _radarTechDomains = radarTechs;
          } else if (_radarTechDomains.isEmpty && targetRoles.isNotEmpty) {
            _radarTechDomains = List.from(targetRoles);
          }
        });
      }

      final linkedInSettings = await _service.getLinkedInAutoApplySettings();
      if (mounted && linkedInSettings.isNotEmpty) {
        setState(() {
          if (linkedInSettings['apifyToken1'] != null && _apifyToken1Controller.text.isEmpty) {
            _apifyToken1Controller.text = linkedInSettings['apifyToken1'];
          }
          if (linkedInSettings['apifyToken2'] != null && _apifyToken2Controller.text.isEmpty) {
            _apifyToken2Controller.text = linkedInSettings['apifyToken2'];
          }
          if (linkedInSettings['apifyToken3'] != null && _apifyToken3Controller.text.isEmpty) {
            _apifyToken3Controller.text = linkedInSettings['apifyToken3'];
          }
          final lRoles = List<String>.from(linkedInSettings['targetRoles'] ?? []);
          if (lRoles.isNotEmpty) {
            _linkedInRolesController.text = lRoles.join(', ');
          }
          if (linkedInSettings['minExpYears'] != null) {
            _linkedInMinExpController.text = linkedInSettings['minExpYears'].toString();
          }
          if (linkedInSettings['maxExpYears'] != null) {
            _linkedInMaxExpController.text = linkedInSettings['maxExpYears'].toString();
          }
          if (linkedInSettings['enabled'] != null) {
            _linkedInAutoApplyEnabled = linkedInSettings['enabled'] == true;
          }
        });
      }
    }
  }

  // ============================================================================
  // DIALOGS & ACTIONS
  // ============================================================================

  void _showAddResumeProfileDialog({ResumeProfile? existingProfile, VoidCallback? onSaved}) {
    final titleController = TextEditingController(text: existingProfile?.title ?? '');
    final rolesController = TextEditingController(text: existingProfile?.targetRoles.join(', ') ?? '');
    String selectedFileName = existingProfile?.fileName ?? '';
    String selectedBase64 = existingProfile?.base64 ?? '';
    bool isDefault = existingProfile?.isDefault ?? (_resumeProfiles.isEmpty);
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.picture_as_pdf_rounded, color: Colors.blueAccent),
                const SizedBox(width: 8),
                Text(
                  existingProfile == null ? 'Add Targeted Resume' : 'Edit Resume Profile',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Save 2–3 targeted profiles (e.g., DevOps/Cloud Resume vs Flutter/Mobile Resume). The AI agent automatically attaches the resume matching the detected role.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: 'Profile Title *',
                      hintText: 'e.g. DevOps & Cloud Resume, Flutter Mobile',
                      prefixIcon: const Icon(Icons.badge_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: rolesController,
                    decoration: InputDecoration(
                      labelText: 'Target Roles & Keywords * (comma-separated)',
                      hintText: 'e.g. DevOps, Cloud, Kubernetes, Terraform, SRE',
                      prefixIcon: const Icon(Icons.tag_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      isDense: true,
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: selectedFileName.isNotEmpty
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selectedFileName.isNotEmpty
                            ? Colors.green.withValues(alpha: 0.3)
                            : Colors.grey.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selectedFileName.isNotEmpty ? Icons.check_circle_rounded : Icons.upload_file_rounded,
                          color: selectedFileName.isNotEmpty ? Colors.green : Colors.grey,
                          size: 24,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            selectedFileName.isNotEmpty ? selectedFileName : 'No PDF selected',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: selectedFileName.isNotEmpty ? FontWeight.bold : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          onPressed: () async {
                            try {
                              final picked = await AppFilePicker.pickPdf();
                              if (picked != null) {
                                if (!picked.name.toLowerCase().endsWith('.pdf')) {
                                  if (dlgCtx.mounted) {
                                    ScaffoldMessenger.of(dlgCtx).showSnackBar(
                                      const SnackBar(content: Text('Please select a PDF file.')),
                                    );
                                  }
                                  return;
                                }
                                setDlgState(() {
                                  selectedFileName = picked.name;
                                  selectedBase64 = base64Encode(picked.bytes);
                                });
                              }
                            } catch (err) {
                              if (dlgCtx.mounted) {
                                ScaffoldMessenger.of(dlgCtx).showSnackBar(
                                  SnackBar(content: Text('Error picking file: $err')),
                                );
                              }
                            }
                          },
                          child: Text(selectedFileName.isNotEmpty ? 'Change' : 'Pick PDF', style: const TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    value: isDefault,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    activeColor: Colors.blueAccent,
                    title: const Text('Set as Default Resume', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    subtitle: const Text('Used if detected job doesn\'t match other profile keywords', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    onChanged: (val) {
                      setDlgState(() => isDefault = val ?? false);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                onPressed: isSaving ? null : () async {
                  final title = titleController.text.trim();
                  final roles = rolesController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
                  if (title.isEmpty) {
                    ScaffoldMessenger.of(dlgCtx).showSnackBar(const SnackBar(content: Text('Please enter a profile title.')));
                    return;
                  }
                  if (roles.isEmpty) {
                    ScaffoldMessenger.of(dlgCtx).showSnackBar(const SnackBar(content: Text('Please enter at least one target role or keyword.')));
                    return;
                  }
                  if (selectedBase64.isEmpty) {
                    ScaffoldMessenger.of(dlgCtx).showSnackBar(const SnackBar(content: Text('Please select a resume PDF file.')));
                    return;
                  }

                  setDlgState(() => isSaving = true);
                  try {
                    final profile = ResumeProfile(
                      id: existingProfile?.id ?? 'profile_${DateTime.now().millisecondsSinceEpoch}',
                      title: title,
                      targetRoles: roles,
                      fileName: selectedFileName,
                      base64: selectedBase64,
                      isDefault: isDefault,
                      updatedAt: DateTime.now(),
                    );
                    await _service.saveResumeProfile(profile);
                    if (mounted) {
                      setState(() {
                        _hasResume = true;
                        if (_resumeFileName.isEmpty || profile.isDefault) {
                          _resumeFileName = profile.fileName;
                        }
                      });
                    }
                    onSaved?.call();
                    if (dlgCtx.mounted) {
                      Navigator.pop(dlgCtx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Resume profile "$title" saved successfully!'), backgroundColor: Colors.green),
                      );
                    }
                  } catch (e) {
                    if (dlgCtx.mounted) {
                      setDlgState(() => isSaving = false);
                      ScaffoldMessenger.of(dlgCtx).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  }
                },
                child: isSaving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Profile', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showJobAssistantSettingsDialog() {
    final nameController = TextEditingController(text: _applicantNameController.text);
    final emailController = TextEditingController(text: _userEmail);
    final passwordController = TextEditingController(text: _userAppPassword);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.settings_suggest_rounded, color: Theme.of(context).primaryColor, size: 26),
                const SizedBox(width: 10),
                const Text('Job Assistant Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section 0: Candidate Profile / Full Name
                    Text(
                      '👤 Candidate Profile & Full Name',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Your full name used across all AI applications, emails, cold outreach pitches, and sign-offs.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Your Full Name (Candidate Name)',
                        hintText: 'e.g. Roshan J or Dhanush',
                        prefixIcon: const Icon(Icons.person_outline_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 12),

                    // Section 1: Multi-Resume Profiles (DevOps vs Flutter vs Cloud)
                    Row(
                      children: [
                        Text(
                          '📄 Targeted Resumes (${_resumeProfiles.length}/3)',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const Spacer(),
                        if (_resumeProfiles.length < 3)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('Add Profile', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            onPressed: () {
                              _showAddResumeProfileDialog(
                                onSaved: () => setDialogState(() {}),
                              );
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Save 2–3 targeted profiles (e.g. DevOps vs Mobile). The agent automatically attaches the resume matching the detected role.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 10),

                    if (_resumeProfiles.isNotEmpty) ...[
                      ..._resumeProfiles.map((p) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: p.isDefault ? Colors.blue.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: p.isDefault ? Colors.blueAccent.withValues(alpha: 0.4) : Colors.grey.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.description_rounded, size: 18, color: p.isDefault ? Colors.blueAccent : Colors.grey[700]),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    p.title,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                                if (p.isDefault)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blueAccent,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('DEFAULT', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                                  ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, size: 16),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  tooltip: 'Edit Profile',
                                  onPressed: () {
                                    _showAddResumeProfileDialog(
                                      existingProfile: p,
                                      onSaved: () => setDialogState(() {}),
                                    );
                                  },
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  tooltip: 'Delete Profile',
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        title: const Text('Delete Profile?'),
                                        content: Text('Delete "${p.title}"?'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                                          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      await _service.deleteResumeProfile(p.id);
                                      setDialogState(() {});
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('File: ${p.fileName}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: p.targetRoles.map((role) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.teal.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
                                ),
                                child: Text(role, style: const TextStyle(fontSize: 10, color: Colors.teal, fontWeight: FontWeight.w600)),
                              )).toList(),
                            ),
                            if (!p.isDefault) ...[
                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  icon: const Icon(Icons.star_outline_rounded, size: 14),
                                  label: const Text('Set as Default', style: TextStyle(fontSize: 11)),
                                  onPressed: () async {
                                    await _service.setDefaultResumeProfile(p.id);
                                    setDialogState(() {});
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      )),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _hasResume
                              ? Colors.green.withValues(alpha: 0.1)
                              : Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _hasResume
                                ? Colors.green.withValues(alpha: 0.3)
                                : Colors.orange.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _hasResume ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                              color: _hasResume ? Colors.green : Colors.orange,
                              size: 24,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _hasResume ? _resumeFileName : 'No Resume Uploaded',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    _hasResume ? 'Master PDF active' : 'Please upload your resume PDF',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueAccent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              onPressed: () async {
                                await _pickMasterResume();
                                setDialogState(() {});
                              },
                              icon: const Icon(Icons.upload_file, size: 16),
                              label: Text(_hasResume ? 'Change' : 'Upload', style: const TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 12),

                    // Section 2: Gmail Sender Credentials
                    Text(
                      '📧 Gmail Sender & App Password',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Enter your Gmail address and 16-character App Password to allow RemindBuddy to dispatch job applications on your behalf.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailController,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: 'Your Gmail Address',
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: 'Gmail App Password (16 characters)',
                        prefixIcon: const Icon(Icons.key_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        helperText: 'Google Account > Security > 2-Step Verification > App Passwords',
                        helperMaxLines: 2,
                        isDense: true,
                      ),
                    ),

                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 12),

                    // Section 3: AI & Search Keys (BYOK)
                    Text(
                      '🔑 AI & Search Keys (BYOK)',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Configure your personal Gemini & Tavily API keys for automated job discovery and recruiter outreach.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.vpn_key_rounded, color: Colors.teal),
                        label: const Text('Manage Gemini & Tavily Keys', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const AIKeysSettingsScreen()),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                onPressed: () async {
                  final newName = nameController.text.trim();
                  final newEmail = emailController.text.trim();
                  final newPass = passwordController.text.trim();
                  await _service.saveApplicantName(newName);
                  await _service.saveUserEmailConfig(newEmail, newPass);
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                  }
                  if (mounted) {
                    setState(() {
                      _applicantNameController.text = newName;
                      _userEmail = newEmail;
                      _userAppPassword = newPass;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Job Assistant settings saved successfully!'), backgroundColor: Colors.green),
                    );
                  }
                },
                child: const Text('Save Settings', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEmailConfigDialog() {
    _showJobAssistantSettingsDialog();
  }

  Future<void> _pickMasterResume() async {
    try {
      final picked = await AppFilePicker.pickPdf();

      if (picked != null) {
        if (!picked.name.toLowerCase().endsWith('.pdf')) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please select a valid PDF file for your resume.')),
            );
          }
          return;
        }

        final b64 = base64Encode(picked.bytes);
        final fileName = picked.name;
        await _service.saveMasterResume(b64, fileName);
        if (mounted) {
          setState(() {
            _resumeFileName = fileName;
            _hasResume = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Master Resume ($fileName) saved successfully!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking resume: $e')),
        );
      }
    }
  }


  Future<void> _pickFromGallery() async {
    try {
      final pickedFiles = await AppFilePicker.pickMultipleImages();
      if (pickedFiles.isNotEmpty) {
        final List<XFile> images = [];
        final List<String> base64List = [];
        for (final img in pickedFiles) {
          images.add(img.toXFile());
          base64List.add(base64Encode(img.bytes));
        }
        setState(() {
          _selectedImageFiles.addAll(images);
          _selectedImagesBase64.addAll(base64List);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking from gallery: $e')),
        );
      }
    }
  }

  Future<void> _pickFromFiles() async {
    try {
      final pickedFiles = await AppFilePicker.pickFiles(
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp'],
        allowMultiple: true,
      );

      if (pickedFiles.isNotEmpty) {
        final List<XFile> images = [];
        final List<String> base64List = [];

        for (final file in pickedFiles) {
          images.add(file.toXFile());
          base64List.add(base64Encode(file.bytes));
        }

        setState(() {
          _selectedImageFiles.addAll(images);
          _selectedImagesBase64.addAll(base64List);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking files: $e')),
        );
      }
    }
  }

  Future<void> _pickJobPosters() async {
    final bool isMobile = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

    if (isMobile) {
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Upload Job Poster Screenshots',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.photo_library, color: Colors.blue),
                  title: const Text('Pick Screenshots from Gallery / Photos'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickFromGallery();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.folder, color: Colors.amber),
                  title: const Text('Browse Files Application'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickFromFiles();
                  },
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      // On web / desktop (Ubuntu, macOS, Windows), directly open native file dialog
      try {
        final pickedFiles = await AppFilePicker.pickMultipleImages();
        if (pickedFiles.isNotEmpty) {
          final List<XFile> images = [];
          final List<String> base64List = [];
          for (final f in pickedFiles) {
            images.add(f.toXFile());
            base64List.add(base64Encode(f.bytes));
          }
          setState(() {
            _selectedImageFiles.addAll(images);
            _selectedImagesBase64.addAll(base64List);
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error picking screenshots: $e')),
          );
        }
      }
    }
  }


  JobApplication? _findExistingApplication(String recipientEmail, String jobTitle, [String? companyName]) {
    final cleanEmail = recipientEmail.toLowerCase().trim();
    final cleanRole = jobTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final cleanComp = (companyName ?? '').toLowerCase().trim();
    if (cleanEmail.isEmpty && cleanComp.isEmpty) return null;

    final allApps = _service.cachedApplications;
    for (final app in allApps) {
      final appEmail = app.recipientEmail.toLowerCase().trim();
      final appRole = app.jobTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      final appComp = app.companyName.toLowerCase().trim();

      // Check if email and role match
      if (cleanEmail.isNotEmpty && appEmail.isNotEmpty && cleanEmail == appEmail && cleanRole.isNotEmpty && cleanRole == appRole) {
        return app;
      }
      // Check if company and role match
      if (cleanComp.isNotEmpty && appComp.isNotEmpty && cleanComp == appComp && cleanRole.isNotEmpty && cleanRole == appRole) {
        return app;
      }
    }
    return null;
  }

  void _showEnlargedImageDialog(int initialIndex) {
    if (initialIndex < 0 || initialIndex >= _selectedImagesBase64.length) return;
    int currentIndex = initialIndex;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final b64 = _selectedImagesBase64[currentIndex];
          final imageBytes = base64Decode(b64);
          final fileName = _selectedImageFiles[currentIndex].name;
          final totalCount = _selectedImagesBase64.length;

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  constraints: BoxConstraints(
                    maxWidth: 720,
                    maxHeight: MediaQuery.of(context).size.height * 0.85,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'Poster ${currentIndex + 1} of $totalCount: $fileName',
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.white),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Interactive Zoomable Image
                      Flexible(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: InteractiveViewer(
                            panEnabled: true,
                            minScale: 0.8,
                            maxScale: 4.0,
                            child: Image.memory(
                              imageBytes,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Previous / Next Navigation if multiple images
                      if (totalCount > 1)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20),
                              onPressed: currentIndex > 0
                                  ? () => setDialogState(() => currentIndex--)
                                  : null,
                            ),
                            const SizedBox(width: 16),
                            Text(
                              '${currentIndex + 1} / $totalCount',
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                            const SizedBox(width: 16),
                            IconButton(
                              icon: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 20),
                              onPressed: currentIndex < totalCount - 1
                                  ? () => setDialogState(() => currentIndex++)
                                  : null,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSelectedImagesPreview() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final count = _selectedImageFiles.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.image_rounded, size: 18, color: Color(0xFF6366F1)),
                const SizedBox(width: 8),
                Text(
                  '$count Poster Screenshot${count > 1 ? 's' : ''} Attached',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
              ],
            ),
            TextButton.icon(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: Colors.redAccent,
              ),
              onPressed: () {
                setState(() {
                  _selectedImageFiles.clear();
                  _selectedImagesBase64.clear();
                });
              },
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Clear All', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 230,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: count,
            itemBuilder: (context, idx) {
              final file = _selectedImageFiles[idx];
              final b64 = _selectedImagesBase64[idx];
              final imageBytes = base64Decode(b64);

              return Container(
                width: 190,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.grey.shade300,
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Full poster image with tap to enlarge
                      GestureDetector(
                        onTap: () => _showEnlargedImageDialog(idx),
                        child: Container(
                          color: isDark ? Colors.black26 : Colors.white,
                          padding: const EdgeInsets.all(4),
                          child: Image.memory(
                            imageBytes,
                            fit: BoxFit.contain,
                            errorBuilder: (ctx, err, stack) => const Center(
                              child: Icon(Icons.broken_image, size: 36, color: Colors.grey),
                            ),
                          ),
                        ),
                      ),
                      // Top Delete Button
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Material(
                          color: Colors.black54,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () {
                              setState(() {
                                _selectedImageFiles.removeAt(idx);
                                _selectedImagesBase64.removeAt(idx);
                              });
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(5.0),
                              child: Icon(Icons.close_rounded, size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                      // Tap to zoom hint badge
                      Positioned(
                        top: 6,
                        left: 6,
                        child: GestureDetector(
                          onTap: () => _showEnlargedImageDialog(idx),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.zoom_in_rounded, size: 12, color: Colors.white70),
                                SizedBox(width: 3),
                                Text(
                                  'Tap to view',
                                  style: TextStyle(color: Colors.white70, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Bottom Label with Poster # and Filename
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [Colors.black87, Colors.transparent],
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6366F1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '#${idx + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  file.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _analyzePostersWithAI() async {
    if (_selectedImagesBase64.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least 1 job poster screenshot!')),
      );
      return;
    }

    setState(() {
      _isAnalyzing = true;
    });

    try {
      final customPrompt = _customScreenshotPromptController.text.trim();
      final jobs = await _service.parseJobPostersWithAI(
        _selectedImagesBase64,
        _uploadMode,
        customPrompt: customPrompt.isEmpty ? null : customPrompt,
        applicantName: _applicantNameController.text.trim().isNotEmpty ? _applicantNameController.text.trim() : null,
      );
      setState(() {
        _extractedJobs = jobs;
        _isAnalyzing = false;
        _selectedImageFiles.clear();
        _selectedImagesBase64.clear();
      });

      if (jobs.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Extracted ${jobs.length} job application(s) with Gemini AI!')),
        );
      }
    } catch (e) {
      setState(() {
        _isAnalyzing = false;
      });
      if (mounted) {
        String msg = e.toString();
        if (msg.contains('deadline-exceeded') || msg.contains('DEADLINE_EXCEEDED')) {
          msg = 'AI analysis timed out processing the image and resume. Please tap "Analyze with Gemini AI" to retry.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg.startsWith('AI') ? msg : 'Error analyzing posters: $msg'),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.amberAccent,
              onPressed: _analyzePostersWithAI,
            ),
          ),
        );
      }
    }
  }

  Future<void> _startAutoApplyInBackground() async {
    if (_selectedImagesBase64.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least 1 job poster screenshot!')),
      );
      return;
    }

    if (_userEmail.isEmpty || _userAppPassword.isEmpty) {
      _showEmailConfigDialog();
      return;
    }

    final imagesToProcess = List<String>.from(_selectedImagesBase64);
    final currentUploadMode = _uploadMode;
    final customPrompt = _customScreenshotPromptController.text.trim();
    final applicantName = _applicantNameController.text.trim().isNotEmpty ? _applicantNameController.text.trim() : null;

    setState(() {
      _selectedImageFiles.clear();
      _selectedImagesBase64.clear();
      _customScreenshotPromptController.clear();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🚀 Screenshots submitted! AI is analyzing and sending applications in the background with safe 30s pacing. You can safely close or leave the app.'),
          duration: Duration(seconds: 6),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    }

    // Run asynchronous background processing
    () async {
      try {
        final jobs = await _service.parseJobPostersWithAI(
          imagesToProcess,
          currentUploadMode,
          customPrompt: customPrompt.isEmpty ? null : customPrompt,
          applicantName: applicantName,
        );

        if (jobs.isEmpty) {
          await NotificationService().showNotification(
            id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            title: '⚠️ No Jobs Detected',
            body: 'Gemini AI could not find any job openings or recruiter emails in the uploaded screenshots.',
            payload: 'JOB_ASSISTANT',
          );
          return;
        }

        int sentCount = 0;

        for (int i = 0; i < jobs.length; i++) {
          final job = jobs[i];
          final recipient = job.recipientEmail.trim();

          if (recipient.isEmpty) {
            await NotificationService().showNotification(
              id: (DateTime.now().millisecondsSinceEpoch ~/ 1000) + i,
              title: '⚠️ Job Application Missing Email',
              body: 'Found "${job.jobTitle}" at "${job.companyName}" but no recruiter email was found on the poster.',
              payload: 'JOB_ASSISTANT',
            );
            continue;
          }

          // Unified Duplicate Check across Manual Scan and Auto-Apply
          final duplicate = _findExistingApplication(recipient, job.jobTitle, job.companyName);
          if (duplicate != null) {
            debugPrint('[JobAssistant] Skipping duplicate job: "${job.jobTitle}" at "${job.companyName}" to $recipient (applied on ${duplicate.appliedAt})');
            await NotificationService().showNotification(
              id: (DateTime.now().millisecondsSinceEpoch ~/ 1000) + i,
              title: 'ℹ️ Skipped Duplicate Application',
              body: 'Role "${job.jobTitle}" at "${job.companyName}" was already applied to on ${DateFormat("MMM d").format(duplicate.appliedAt)}.',
              payload: 'JOB_ASSISTANT',
            );
            continue;
          }

          try {
            await _service.sendJobApplicationEmail(job);
            sentCount++;
          } catch (err) {
            await NotificationService().showNotification(
              id: (DateTime.now().millisecondsSinceEpoch ~/ 1000) + i,
              title: '⚠️ Job Email Delivery Failed',
              body: 'Could not send application for "${job.jobTitle}" at "${job.companyName}" to $recipient: $err',
              payload: 'JOB_ASSISTANT',
            );
          }

          // Rate limiting delay: 30 seconds between consecutive sends to protect Gmail sender reputation
          if (i < jobs.length - 1) {
            await Future.delayed(const Duration(seconds: 30));
          }
        }

        if (sentCount > 0) {
          await NotificationService().showNotification(
            id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            title: '✅ Job Applications Sent Successfully',
            body: 'Auto-applied to $sentCount job(s) from your screenshots! Check Applied History.',
            payload: 'JOB_ASSISTANT',
          );
        }
      } catch (e) {
        debugPrint('[JobAssistant] Background auto-apply error: $e');
        await NotificationService().showNotification(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          title: '⚠️ Background Auto-Apply Failed',
          body: 'Error analyzing screenshots: $e',
          payload: 'JOB_ASSISTANT',
        );
      }
    }();
  }

  Future<void> _generateManualJobApplicationWithAI() async {
    final companyName = _manualCompanyNameController.text.trim();
    final jobTitle = _manualJobTitleController.text.trim();
    final companyUrl = _manualCompanyUrlController.text.trim();
    final recipientEmails = _manualRecipientEmailsController.text.trim();
    final companyNotes = _manualCompanyNotesController.text.trim();
    final customPrompt = _manualCustomPromptController.text.trim();

    if (companyName.isEmpty || jobTitle.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter Company Name and Job Role Title.')),
      );
      return;
    }

    setState(() {
      _isGeneratingManual = true;
    });

    try {
      final newJob = await _service.generateManualJobApplicationWithAI(
        companyName: companyName,
        jobTitle: jobTitle,
        companyUrl: companyUrl.isEmpty ? null : companyUrl,
        recipientEmails: recipientEmails.isEmpty ? null : recipientEmails,
        companyNotes: companyNotes.isEmpty ? null : companyNotes,
        customPrompt: customPrompt.isEmpty ? null : customPrompt,
        applicantName: _applicantNameController.text.trim().isNotEmpty ? _applicantNameController.text.trim() : null,
      );

      setState(() {
        _extractedJobs.insert(0, newJob);
        _isGeneratingManual = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Generated application for $jobTitle at $companyName with Gemini AI!')),
        );
      }
    } catch (e) {
      setState(() {
        _isGeneratingManual = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating application: $e')),
        );
      }
    }
  }

  Future<void> _refineJobWithAI(int index) async {
    final app = _extractedJobs[index];
    final promptCtrl = _refinePromptControllers[index];
    final userPrompt = promptCtrl?.text.trim() ?? '';

    if (userPrompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an instruction for AI refinement (e.g., "Make it more concise").')),
      );
      return;
    }

    setState(() {
      _refiningMap[index] = true;
    });

    try {
      final currentSubject = _subjectControllers[index]?.text ?? app.generatedSubject;
      final currentCoverLetter = _bodyControllers[index]?.text ?? app.generatedCoverLetter;

      final res = await _service.refineCoverLetterWithAI(
        currentSubject: currentSubject,
        currentCoverLetter: currentCoverLetter,
        userPrompt: userPrompt,
        jobTitle: app.jobTitle,
        companyName: app.companyName,
        applicantName: _applicantNameController.text.trim().isNotEmpty ? _applicantNameController.text.trim() : null,
      );

      final newSubject = res['generatedSubject'] ?? currentSubject;
      final newBody = res['generatedCoverLetter'] ?? currentCoverLetter;

      setState(() {
        _extractedJobs[index] = JobApplication(
          id: app.id,
          jobTitle: app.jobTitle,
          companyName: app.companyName,
          recipientEmail: _emailControllers[index]?.text ?? app.recipientEmail,
          extractedSkills: app.extractedSkills,
          generatedSubject: newSubject,
          generatedCoverLetter: newBody,
          status: app.status,
          appliedAt: app.appliedAt,
          posterImageUrls: app.posterImageUrls,
          errorMessage: app.errorMessage,
        );

        if (_subjectControllers.containsKey(index)) {
          _subjectControllers[index]!.text = newSubject;
        }
        if (_bodyControllers.containsKey(index)) {
          _bodyControllers[index]!.text = newBody;
        }
        promptCtrl?.clear();
        _refiningMap[index] = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cover letter refined successfully with AI!')),
        );
      }
    } catch (e) {
      setState(() {
        _refiningMap[index] = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error refining cover letter: $e')),
        );
      }
    }
  }

  Future<void> _sendApplicationEmail(JobApplication originalApp, int index) async {
    if (_userEmail.isEmpty || _userAppPassword.isEmpty) {
      _showEmailConfigDialog();
      return;
    }

    final recipient = (_emailControllers[index]?.text ?? originalApp.recipientEmail).trim();
    final subject = (_subjectControllers[index]?.text ?? originalApp.generatedSubject).trim();
    final body = (_bodyControllers[index]?.text ?? originalApp.generatedCoverLetter).trim();

    if (recipient.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a recipient HR email address.')),
      );
      return;
    }

    final appToSend = JobApplication(
      id: originalApp.id,
      jobTitle: originalApp.jobTitle,
      companyName: originalApp.companyName,
      recipientEmail: recipient,
      extractedSkills: originalApp.extractedSkills,
      generatedSubject: subject,
      generatedCoverLetter: body,
      status: originalApp.status,
      appliedAt: originalApp.appliedAt,
      posterImageUrls: originalApp.posterImageUrls,
      errorMessage: originalApp.errorMessage,
    );

    final duplicate = _findExistingApplication(recipient, originalApp.jobTitle, originalApp.companyName);
    if (duplicate != null) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.history_rounded, color: Colors.amber, size: 24),
              SizedBox(width: 8),
              Text('Already Applied', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            'You previously applied for the role "${originalApp.jobTitle}" at "${originalApp.companyName}" ($recipient) on ${_formatRelativeTimestamp(duplicate.appliedAt)} (${duplicate.isAutoApplied ? "Auto-Apply" : "Manual"}).\n\nAre you sure you want to send another application email for this same role?',
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Send Anyway'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    if (!mounted) return;

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sending application email in background...')),
      );

      await _service.sendJobApplicationEmail(appToSend);

      setState(() {
        _extractedJobs.removeAt(index);
        _emailControllers.remove(index)?.dispose();
        _subjectControllers.remove(index)?.dispose();
        _bodyControllers.remove(index)?.dispose();
        _refinePromptControllers.remove(index)?.dispose();
        _refiningMap.remove(index);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Job application email sent to $recipient!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send email: $e')),
        );
      }
    }
  }

  Future<void> _openNativeMailApp(JobApplication originalApp, int index) async {
    final recipient = (_emailControllers[index]?.text ?? originalApp.recipientEmail).trim();
    final subject = (_subjectControllers[index]?.text ?? originalApp.generatedSubject).trim();
    final body = (_bodyControllers[index]?.text ?? originalApp.generatedCoverLetter).trim();

    final uri = Uri(
      scheme: 'mailto',
      path: recipient,
      queryParameters: {
        'subject': subject,
        'body': body,
      },
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch mail application.')),
        );
      }
    }
  }

  bool _isSendingAll = false;

  Future<void> _sendAllEmails() async {
    if (_extractedJobs.isEmpty) return;

    if (_userEmail.isEmpty || _userAppPassword.isEmpty) {
      _showEmailConfigDialog();
      return;
    }

    setState(() {
      _isSendingAll = true;
    });

    int sentCount = 0;
    int failCount = 0;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Sending ${_extractedJobs.length} job application email(s) in background...'),
        duration: const Duration(seconds: 3),
      ),
    );

    final jobsToProcess = List<JobApplication>.from(_extractedJobs);

    // Detect duplicate applications in the extracted list
    final duplicateIndexes = <int>{};
    for (int i = 0; i < jobsToProcess.length; i++) {
      final j = jobsToProcess[i];
      final rec = (_emailControllers[i]?.text ?? j.recipientEmail).trim();
      if (_findExistingApplication(rec, j.jobTitle, j.companyName) != null) {
        duplicateIndexes.add(i);
      }
    }

    if (duplicateIndexes.isNotEmpty) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.history_rounded, color: Colors.amber, size: 22),
              SizedBox(width: 8),
              Text('Duplicate Roles Found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            '${duplicateIndexes.length} of ${jobsToProcess.length} jobs were already applied to previously for the same role.\n\nWould you like to skip duplicates and only send new applications, or send all anyway?',
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, 'send_all'),
              child: const Text('Send All Anyway'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, 'skip_duplicates'),
              child: const Text('Skip Duplicates'),
            ),
          ],
        ),
      );

      if (!mounted) return;

      if (choice == null || choice == 'cancel') {
        setState(() => _isSendingAll = false);
        return;
      }

      if (choice == 'skip_duplicates') {
        final filteredList = <JobApplication>[];
        for (int i = 0; i < jobsToProcess.length; i++) {
          if (!duplicateIndexes.contains(i)) {
            filteredList.add(jobsToProcess[i]);
          }
        }
        jobsToProcess.clear();
        jobsToProcess.addAll(filteredList);
      }
    }

    for (int i = 0; i < jobsToProcess.length; i++) {
      final originalApp = jobsToProcess[i];
      final recipient = (_emailControllers[i]?.text ?? originalApp.recipientEmail).trim();
      final subject = (_subjectControllers[i]?.text ?? originalApp.generatedSubject).trim();
      final body = (_bodyControllers[i]?.text ?? originalApp.generatedCoverLetter).trim();

      if (recipient.isEmpty) {
        failCount++;
        continue;
      }

      final appToSend = JobApplication(
        id: originalApp.id,
        jobTitle: originalApp.jobTitle,
        companyName: originalApp.companyName,
        recipientEmail: recipient,
        extractedSkills: originalApp.extractedSkills,
        generatedSubject: subject,
        generatedCoverLetter: body,
        status: originalApp.status,
        appliedAt: originalApp.appliedAt,
        posterImageUrls: originalApp.posterImageUrls,
        errorMessage: originalApp.errorMessage,
      );

      try {
        await _service.sendJobApplicationEmail(appToSend);
        sentCount++;
      } catch (e) {
        debugPrint("Error sending email to $recipient: $e");
        failCount++;
      }

      // Safe pacing: 30 seconds between sends to protect Gmail sender reputation
      if (i < jobsToProcess.length - 1) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Email ${i + 1} of ${jobsToProcess.length} sent. Pausing 30s to protect Gmail account...'),
              duration: const Duration(seconds: 4),
            ),
          );
        }
        await Future.delayed(const Duration(seconds: 30));
      }
    }

    for (var ctrl in _emailControllers.values) {
      ctrl.dispose();
    }
    for (var ctrl in _subjectControllers.values) {
      ctrl.dispose();
    }
    for (var ctrl in _bodyControllers.values) {
      ctrl.dispose();
    }
    for (var ctrl in _refinePromptControllers.values) {
      ctrl.dispose();
    }

    setState(() {
      _extractedJobs.clear();
      _emailControllers.clear();
      _subjectControllers.clear();
      _bodyControllers.clear();
      _refinePromptControllers.clear();
      _refiningMap.clear();
      _isSendingAll = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🚀 Successfully sent $sentCount job application email(s)!${failCount > 0 ? " ($failCount missing HR emails)" : ""}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  // ============================================================================
  // AUTO-APPLY AGENT ACTIONS & TAB
  // ============================================================================

  Future<void> _saveAutoApplySettings() async {
    var roles = _targetRolesController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    var locs = _locationsController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final minExp = _isFresher ? 0 : (int.tryParse(_minExpController.text.trim()) ?? 0);
    final maxExp = _isFresher ? 0 : (int.tryParse(_maxExpController.text.trim()) ?? 3);

    // Safeguard: do not wipe existing roles/locations if user hasn't typed in new ones but had radar domains/locs
    if (roles.isEmpty && _radarTechDomains.isNotEmpty) {
      roles = List.from(_radarTechDomains);
    }
    if (locs.isEmpty && _radarLocations.isNotEmpty) {
      locs = List.from(_radarLocations);
    }

    setState(() => _isSavingAutoSettings = true);
    try {
      final name = _applicantNameController.text.trim();
      await _service.saveApplicantName(name);
      await _service.saveAutoApplySettings(
        enabled: _autoApplyEnabled,
        targetRoles: roles,
        locations: locs,
        excludedCompanies: _excludedCompanies,
        minExpYears: minExp,
        maxExpYears: maxExp,
        isFresher: _isFresher,
        maxPerRun: 6,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Auto-Apply settings saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving settings: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingAutoSettings = false);
      }
    }
  }

  Future<void> _runAutoApplyNow() async {
    final bool hasAnyResume = _hasResume || _resumeProfiles.isNotEmpty;
    if (!hasAnyResume) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload your Resume PDF first in Settings (top right icon).')),
      );
      _showJobAssistantSettingsDialog();
      return;
    }
    if (_userEmail.isEmpty || _userAppPassword.isEmpty) {
      _showJobAssistantSettingsDialog();
      return;
    }

    final roles = _targetRolesController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (roles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please specify at least one target role (e.g. .NET Developer, Software Engineer).'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    final locs = _locationsController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final minExp = int.tryParse(_minExpController.text.trim()) ?? 0;
    final maxExp = int.tryParse(_maxExpController.text.trim()) ?? 3;

    setState(() {
      _isRunningAutoApply = true;
      _autoApplyStatusMessage = 'Searching LinkedIn & job boards for verified HR postings ($minExp-$maxExp yrs)...';
    });

    try {
      final res = await _service.triggerAutoJobDiscoveryAndApply(
        applicantName: _applicantNameController.text.trim().isNotEmpty ? _applicantNameController.text.trim() : null,
        targetRoles: roles,
        locations: locs,
        excludedCompanies: _excludedCompanies,
        minExpYears: minExp,
        maxExpYears: maxExp,
        maxApplications: 4,
      );

      final count = res['appliedCount'] ?? 0;
      final msg = res['message'] ?? 'Discovery complete.';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(count > 0 ? '🚀 Successfully auto-applied to $count new job(s)!' : msg),
            backgroundColor: count > 0 ? Colors.green : Colors.blueAccent,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String errorMsg;
        if (e is FirebaseFunctionsException) {
          errorMsg = e.message ?? e.toString();
        } else if (e is FirebaseException) {
          errorMsg = e.message ?? e.toString();
        } else {
          errorMsg = e.toString().replaceFirst('Exception: ', '');
        }
        if (errorMsg.contains('not-found') || errorMsg.contains('NOT_FOUND')) {
          errorMsg = 'Backend Cloud Function needs deployment. Once deployed to Firebase, auto-discovery & apply will run live.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRunningAutoApply = false;
          _autoApplyStatusMessage = '';
        });
      }
    }
  }

  Widget _buildResponseBadge(JobApplication app, bool isDark) {
    final bool isBounce = app.isBounced || app.status == 'bounced' || app.responseType == 'bounced';
    final type = isBounce ? 'bounced' : (app.responseType ?? 'reply');
    Color bgColor;
    Color textColor;
    IconData icon;
    String label;

    switch (type) {
      case 'bounced':
        bgColor = const Color(0xFFEF4444).withValues(alpha: 0.18);
        textColor = isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
        icon = Icons.error_outline_rounded;
        label = '⚠️ Address Not Found';
        break;
      case 'interview_invite':
        bgColor = const Color(0xFF8B5CF6).withValues(alpha: 0.2);
        textColor = isDark ? const Color(0xFFA78BFA) : const Color(0xFF6D28D9);
        icon = Icons.event_available_rounded;
        label = '🎉 Interview Invite';
        break;
      case 'assessment':
        bgColor = const Color(0xFF3B82F6).withValues(alpha: 0.2);
        textColor = isDark ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8);
        icon = Icons.assignment_turned_in_rounded;
        label = '📝 Assessment Sent';
        break;
      case 'hr_query':
        bgColor = const Color(0xFF10B981).withValues(alpha: 0.2);
        textColor = isDark ? const Color(0xFF34D399) : const Color(0xFF047857);
        icon = Icons.chat_bubble_outline_rounded;
        label = '💬 Recruiter Replied';
        break;
      case 'acknowledgment':
        bgColor = const Color(0xFF06B6D4).withValues(alpha: 0.2);
        textColor = isDark ? const Color(0xFF22D3EE) : const Color(0xFF0E7490);
        icon = Icons.mark_email_read_rounded;
        label = '📋 Application Acknowledged';
        break;
      case 'rejection':
        bgColor = Colors.grey.withValues(alpha: 0.2);
        textColor = isDark ? Colors.grey.shade400 : Colors.grey.shade700;
        icon = Icons.cancel_outlined;
        label = '❌ Not Selected';
        break;
      default:
        bgColor = const Color(0xFF10B981).withValues(alpha: 0.2);
        textColor = isDark ? const Color(0xFF34D399) : const Color(0xFF047857);
        icon = Icons.mark_email_unread_rounded;
        label = '📬 Reply Received';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: textColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecruiterReplyCard(JobApplication app, bool isDark) {
    final bool isBounce = app.isBounced || app.status == 'bounced' || app.responseType == 'bounced';
    final timeStr = app.replyReceivedAt != null
        ? DateFormat('dd MMM yyyy, h:mm a').format(app.replyReceivedAt!)
        : 'Recently';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isBounce
              ? (isDark
                  ? [const Color(0xFF7F1D1D).withValues(alpha: 0.35), const Color(0xFF450A0A).withValues(alpha: 0.45)]
                  : [const Color(0xFFFEF2F2), const Color(0xFFFEE2E2)])
              : (isDark
                  ? [const Color(0xFF064E3B).withValues(alpha: 0.35), const Color(0xFF042F2E).withValues(alpha: 0.45)]
                  : [const Color(0xFFECFDF5), const Color(0xFFD1FAE5)]),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isBounce
              ? const Color(0xFFEF4444).withValues(alpha: 0.4)
              : const Color(0xFF10B981).withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    isBounce ? Icons.error_outline_rounded : Icons.mark_email_unread_rounded,
                    color: isBounce ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isBounce ? 'Delivery Failure: Address Not Found' : 'Recruiter Response',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isBounce
                          ? (isDark ? const Color(0xFFF87171) : const Color(0xFF991B1B))
                          : (isDark ? const Color(0xFF34D399) : const Color(0xFF065F46)),
                    ),
                  ),
                ],
              ),
              Text(
                timeStr,
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white60 : Colors.grey.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (app.replySender != null && app.replySender!.isNotEmpty) ...[
            Text(
              'From: ${app.replySender}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 2),
          ],
          if (app.replySubject != null && app.replySubject!.isNotEmpty) ...[
            Text(
              'Subject: ${app.replySubject}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
          ],
          if (app.replySnippet != null && app.replySnippet!.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
              ),
              child: Text(
                app.replySnippet!,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.35,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (app.actionRequired != null && app.actionRequired!.isNotEmpty && app.actionRequired != 'none') ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.notification_important_rounded, size: 12, color: Colors.amber),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'Action: ${app.actionRequired}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () async {
                final query = Uri.encodeComponent(app.replySender ?? app.recipientEmail);
                final webUrl = Uri.parse('https://mail.google.com/mail/u/0/#search/$query');
                if (await canLaunchUrl(webUrl)) {
                  await launchUrl(webUrl, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 13, color: Color(0xFF10B981)),
              label: const Text(
                'Open in Gmail',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // HUB MENU & FEATURE NAVIGATION (Finance-style Card Grid)
  // ============================================================================

  Widget _getFeatureTitle(int index) {
    switch (index) {
      case 0:
        return const Text('Auto-Apply Agent ⚡', style: TextStyle(fontWeight: FontWeight.bold));
      case 1:
        return const Text('Career Portals & ATS Matcher 🏢', style: TextStyle(fontWeight: FontWeight.bold));
      case 2:
        return const Text('LinkedIn Hiring Posts 💼', style: TextStyle(fontWeight: FontWeight.bold));
      case 3:
        return const Text('Cold Outreach 👥', style: TextStyle(fontWeight: FontWeight.bold));
      case 4:
        return const Text('Manual Scan & Apply 📸', style: TextStyle(fontWeight: FontWeight.bold));
      case 5:
        return const Text('Applied Job History 📜', style: TextStyle(fontWeight: FontWeight.bold));
      default:
        return const Text('AI Job Applicant 💼', style: TextStyle(fontWeight: FontWeight.bold));
    }
  }

  Widget _buildApplicantHubGrid() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color subtextColor = isDark ? Colors.white70 : Colors.black54;
    final Color cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;

    final List<Map<String, dynamic>> features = [
      {
        'index': 0,
        'title': 'Auto-Apply Agent ⚡',
        'subtitle': 'Autonomous recruiter search & personalized email applications via Tavily',
        'icon': Icons.bolt_rounded,
        'gradient': [const Color(0xFF3B82F6), const Color(0xFF1D4ED8)],
      },
      {
        'index': 1,
        'title': 'Career Portals & ATS Matcher 🏢',
        'subtitle': 'Direct Greenhouse, Lever & Ashby openings (<48h) + 1-Click Tailored PDF Resume',
        'isNew': true,
        'icon': Icons.apartment_rounded,
        'gradient': [const Color(0xFF10B981), const Color(0xFF047857)],
      },
      {
        'index': 2,
        'title': 'LinkedIn Hiring Posts 💼',
        'subtitle': 'Real-time hiring posts from creators & recruiters with direct email apply',
        'icon': Icons.dynamic_feed_rounded,
        'gradient': [const Color(0xFF0EA5E9), const Color(0xFF0284C7)],
      },
      {
        'index': 3,
        'title': 'Cold Outreach 👥',
        'subtitle': 'Targeted founder & hiring manager networking and personalized outreach',
        'icon': Icons.people_alt_rounded,
        'gradient': [const Color(0xFFA855F7), const Color(0xFF7E22CE)],
      },
      {
        'index': 4,
        'title': 'Manual Scan & Apply 📸',
        'subtitle': 'Upload job screenshots, hiring flyers or paste JDs to analyze & apply',
        'icon': Icons.add_photo_alternate_rounded,
        'gradient': [const Color(0xFFF59E0B), const Color(0xFFB45309)],
      },
      {
        'index': 5,
        'title': 'Applied Job History 📜',
        'subtitle': 'Unified application tracker, recruiter replies, follow-ups & sent logs',
        'icon': Icons.history_rounded,
        'gradient': [const Color(0xFF64748B), const Color(0xFF334155)],
      },
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWide = constraints.maxWidth > 700;

        Widget buildCard(Map<String, dynamic> feat) {
          final gradient = feat['gradient'] as List<Color>;
          return Card(
            elevation: isDark ? 4 : 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            color: cardBg,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                setState(() {
                  _selectedFeatureIndex = feat['index'] as int;
                });
              },
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: cardBg,
                  border: Border.all(color: gradient.first.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: gradient),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(feat['icon'] as IconData, color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  feat['title'] as String,
                                  style: GoogleFonts.outfit(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (feat['isNew'] == true) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFF10B981), width: 0.8),
                                  ),
                                  child: const Text(
                                    'NEW',
                                    style: TextStyle(
                                      color: Color(0xFF10B981),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            feat['subtitle'] as String,
                            style: TextStyle(color: subtextColor, fontSize: 12, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_forward_ios_rounded, color: subtextColor, size: 16),
                  ],
                ),
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.work_rounded, color: Colors.blueAccent, size: 28),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Job Applicant Hub 💼',
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    Text(
                      'Select a module to discover, tailor & apply to jobs',
                      style: TextStyle(color: subtextColor, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (isWide)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 2.8,
                ),
                itemCount: features.length,
                itemBuilder: (context, idx) => buildCard(features[idx]),
              )
            else
              ...features.map((feat) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: buildCard(feat),
                  )),
          ],
        );
      },
    );
  }

  // ============================================================================
  // BUILD METHOD
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _selectedFeatureIndex == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectedFeatureIndex != null) {
          setState(() {
            _selectedFeatureIndex = null;
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _selectedFeatureIndex != null
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Back to Hub Menu',
                  onPressed: () {
                    setState(() {
                      _selectedFeatureIndex = null;
                    });
                  },
                )
              : null,
          title: _selectedFeatureIndex == null
              ? Text(
                  'AI Job Applicant 💼',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                )
              : _getFeatureTitle(_selectedFeatureIndex!),
          elevation: 2,
          actions: [
            IconButton(
              icon: const Icon(Icons.receipt_long_rounded),
              tooltip: 'Automation Run Logs',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const FeatureLogsScreen(
                      title: 'AI Applicant Logs',
                      allowedFeatures: ['auto_apply', 'cold_outreach', 'linkedin_auto_apply', 'career_portals'],
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: StreamBuilder<List<JobApplication>>(
                initialData: _service.cachedApplications,
                stream: _applicationsStream,
                builder: (context, appSnap) {
                  return StreamBuilder<List<NetworkingLead>>(
                    initialData: _service.cachedLeads,
                    stream: _networkingLeadsStream,
                    builder: (context, leadSnap) {
                      final appReplies = (appSnap.data ?? [])
                          .where((a) => (a.status == 'reply_received' || a.isBounced) && !a.isReplyDismissed)
                          .length;
                      final leadReplies = (leadSnap.data ?? [])
                          .where((l) => (l.status == 'replied' || l.isBounced) && !l.isReplyDismissed)
                          .length;
                      final totalReplies = appReplies + leadReplies;

                      if (totalReplies > 0) {
                        return Badge(
                          label: Text('$totalReplies'),
                          backgroundColor: Colors.amber,
                          textColor: Colors.black,
                          child: const Icon(Icons.mark_email_unread_rounded),
                        );
                      }
                      return const Icon(Icons.mark_email_read_rounded);
                    },
                  );
                },
              ),
              tooltip: 'Recruiter & Founder Replies Hub',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const JobRepliesScreen()),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Job Assistant Settings',
              onPressed: _showJobAssistantSettingsDialog,
            ),
          ],
        ),
        body: _selectedFeatureIndex == null
            ? _buildApplicantHubGrid()
            : IndexedStack(
                index: _selectedFeatureIndex!,
                children: [
                  _KeepAliveTabWrapper(child: _buildAutoApplyTab()),
                  _KeepAliveTabWrapper(child: _buildCareerPortalsTab()),
                  _KeepAliveTabWrapper(child: _buildLinkedInPostsTab()),
                  _KeepAliveTabWrapper(child: _buildNetworkingTab()),
                  _KeepAliveTabWrapper(child: _buildNewApplicationTab()),
                  _KeepAliveTabWrapper(child: _buildHistoryTab()),
                ],
              ),
      ),
    );
  }

  // ============================================================================
  // CAREER PORTALS & ATS MATCHER TAB (< 48h)
  // ============================================================================

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes <= 0 ? 1 : diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }

  Future<void> _discoverCareerPortals({bool force = false}) async {
    if (_isDiscoveringPortals) return;
    setState(() => _isDiscoveringPortals = true);
    try {
      final res = await _service.triggerCareerPortalDiscovery(
        forceRefresh: force,
        customRole: _portalRoleController.text.trim().isNotEmpty ? _portalRoleController.text.trim() : null,
      );
      final msg = res['message']?.toString() ?? 'Career portal discovery complete.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Career portal discovery failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDiscoveringPortals = false);
    }
  }

  Future<void> _downloadTailoredPdf(CareerPortalJob job) async {
    try {
      final b64 = job.tailoredResumePdfBase64;
      if (b64 != null && b64.isNotEmpty) {
        final cleanB64 = b64.replaceFirst(RegExp(r'^data:application\/pdf;base64,'), '');
        final bytes = base64Decode(cleanB64);
        final safeCompany = job.companyName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
        final safeRole = job.jobTitle.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
        final fileName = '${safeCompany}_${safeRole}_Tailored_Resume.pdf';

        if (kIsWeb) {
          final dataUrl = 'data:application/pdf;base64,$cleanB64';
          await launchUrl(Uri.parse(dataUrl));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Downloading tailored resume for ${job.companyName}...'),
                backgroundColor: const Color(0xFF10B981),
              ),
            );
          }
          return;
        }

        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(bytes);

        await Share.shareXFiles(
          [XFile(filePath, mimeType: 'application/pdf', name: fileName)],
          text: 'Tailored ATS Resume for ${job.jobTitle} at ${job.companyName}',
          subject: fileName,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Tailored PDF ready for ${job.companyName}! Attach it on the portal.'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
        }
      } else if (job.tailoredResumePdfUrl != null && job.tailoredResumePdfUrl!.isNotEmpty) {
        await launchUrl(Uri.parse(job.tailoredResumePdfUrl!), mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Resume PDF is still generating. Please tap Discover Portals to refresh.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error downloading tailored resume: $e')),
        );
      }
    }
  }

  Future<void> _openPortalAndApply(CareerPortalJob job) async {
    try {
      final uri = Uri.tryParse(job.portalUrl);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        await _service.updateCareerPortalJobStatus(job.id, 'applied');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Opening ${job.companyName} portal • Marked as Applied ✓'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening portal: $e')),
        );
      }
    }
  }

  Widget _buildCareerPortalsTab() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;

    return StreamBuilder<List<CareerPortalJob>>(
      stream: _service.streamCareerPortalJobs(),
      builder: (context, snapshot) {
        final allJobs = snapshot.data ?? [];

        // Apply portal filter
        final filteredJobs = allJobs.where((j) {
          if (_portalFilter == 'greenhouse' && j.portalType != 'greenhouse') return false;
          if (_portalFilter == 'lever' && j.portalType != 'lever') return false;
          if (_portalFilter == 'ashby' && j.portalType != 'ashby') return false;
          if (_portalFilter == 'high_match' && j.atsScore < 80) return false;
          if (_portalFilter == 'applied' && j.status != 'applied') return false;

          if (_portalSearchQuery.trim().isNotEmpty) {
            final q = _portalSearchQuery.toLowerCase();
            final matchesSearch = j.companyName.toLowerCase().contains(q) ||
                j.jobTitle.toLowerCase().contains(q) ||
                j.location.toLowerCase().contains(q) ||
                j.matchedSkills.any((s) => s.toLowerCase().contains(q));
            if (!matchesSearch) return false;
          }
          return true;
        }).toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Top Hero Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF065F46), Color(0xFF047857), Color(0xFF0F766E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF047857).withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.apartment_rounded, color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Direct ATS Career Portals (< 48h) 🏢',
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Official Greenhouse, Lever & Ashby jobs verified < 48 hours with 1-click tailored resume PDF ready to attach.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.9),
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isDiscoveringPortals ? null : () => _discoverCareerPortals(force: true),
                          icon: _isDiscoveringPortals
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF065F46)),
                                )
                              : const Icon(Icons.radar_rounded, size: 18),
                          label: Text(
                            _isDiscoveringPortals ? 'Discovering & Tailoring...' : 'Discover Portals (< 48h)',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF065F46),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Search Bar
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? Colors.blueGrey.shade800 : Colors.grey.shade300,
                ),
              ),
              child: TextField(
                controller: _portalSearchController,
                onChanged: (val) => setState(() => _portalSearchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search by role, company or skill...',
                  hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _portalSearchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _portalSearchController.clear();
                            setState(() => _portalSearchQuery = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildPortalFilterChip('all', 'All (<48h)'),
                  const SizedBox(width: 8),
                  _buildPortalFilterChip('greenhouse', 'Greenhouse 🟢'),
                  const SizedBox(width: 8),
                  _buildPortalFilterChip('lever', 'Lever 🔵'),
                  const SizedBox(width: 8),
                  _buildPortalFilterChip('ashby', 'Ashby 🟣'),
                  const SizedBox(width: 8),
                  _buildPortalFilterChip('high_match', 'High Match (≥80%) ⭐'),
                  const SizedBox(width: 8),
                  _buildPortalFilterChip('applied', 'Applied ✓'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Job Cards List
            if (filteredJobs.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                margin: const EdgeInsets.only(top: 20),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? Colors.blueGrey.shade800 : Colors.grey.shade300,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.apartment_rounded,
                      size: 48,
                      color: isDark ? Colors.white30 : Colors.black26,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No Career Portal Openings Found',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tap "Discover Portals" above to fetch fresh openings from Greenhouse, Lever, and Ashby verified within the last 48 hours.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              )
            else
              ...filteredJobs.map((job) => _buildCareerPortalJobCard(job, isDark, cardBg, textColor)),
          ],
        );
      },
    );
  }

  Widget _buildPortalFilterChip(String key, String label) {
    final bool isSelected = _portalFilter == key;
    return FilterChip(
      selected: isSelected,
      label: Text(label, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      onSelected: (_) => setState(() => _portalFilter = key),
      selectedColor: const Color(0xFF10B981).withValues(alpha: 0.2),
      checkmarkColor: const Color(0xFF10B981),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  Widget _buildCareerPortalJobCard(CareerPortalJob job, bool isDark, Color cardBg, Color textColor) {
    Color portalColor = const Color(0xFF10B981); // default green
    String portalLabel = 'Greenhouse';
    if (job.portalType == 'lever') {
      portalColor = const Color(0xFF3B82F6);
      portalLabel = 'Lever';
    } else if (job.portalType == 'ashby') {
      portalColor = const Color(0xFFA855F7);
      portalLabel = 'Ashby';
    } else if (job.portalType == 'workday') {
      portalColor = const Color(0xFFF59E0B);
      portalLabel = 'Workday';
    }

    final bool isApplied = job.status == 'applied';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: isDark ? 4 : 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      color: cardBg,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Company, Title, Portal Badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: portalColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: portalColor.withValues(alpha: 0.3)),
                  ),
                  child: Center(
                    child: Text(
                      job.companyName.isNotEmpty ? job.companyName.substring(0, 1).toUpperCase() : 'C',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: portalColor),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              job.companyName,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: portalColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: portalColor.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              portalLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: portalColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        job.jobTitle,
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined, size: 12, color: isDark ? Colors.white54 : Colors.black45),
                          const SizedBox(width: 3),
                          Text(
                            job.location,
                            style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black45),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.access_time_rounded, size: 12, color: Color(0xFF10B981)),
                          const SizedBox(width: 3),
                          Text(
                            _formatTimeAgo(job.postedAt),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ATS Score & Match Reasoning Box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.blueGrey.shade900 : Colors.grey.shade200,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '⭐ ${job.atsScore}% ATS Match',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Verified < 48 Hours',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                  if (job.matchReasoning.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      job.matchReasoning,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Skills & Injected Keywords
            if (job.matchedSkills.isNotEmpty || job.injectedKeywords.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  ...job.matchedSkills.take(4).map(
                        (s) => Chip(
                          label: Text(s, style: const TextStyle(fontSize: 10)),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          backgroundColor: Colors.blue.withValues(alpha: 0.1),
                          side: BorderSide(color: Colors.blue.withValues(alpha: 0.3)),
                        ),
                      ),
                  ...job.injectedKeywords.take(3).map(
                        (k) => Chip(
                          label: Text('+ $k', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.1),
                          side: BorderSide(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                        ),
                      ),
                ],
              ),
            const SizedBox(height: 14),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _downloadTailoredPdf(job),
                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 16, color: Color(0xFFEF4444)),
                    label: const Text(
                      'Download PDF',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      side: BorderSide(color: isDark ? Colors.blueGrey.shade700 : Colors.grey.shade400),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _openPortalAndApply(job),
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: Text(
                      isApplied ? 'Applied ✓' : 'Apply on Portal',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isApplied ? Colors.grey.shade700 : const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // REUSABLE MONTH SELECTOR & NUMBERED PAGINATION HELPERS
  // ============================================================================

  Widget _buildMonthSelector({
    required DateTime selectedMonth,
    required ValueChanged<DateTime> onMonthChanged,
    required bool isDark,
  }) {
    final monthStr = DateFormat('MMMM yyyy').format(selectedMonth);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.blueGrey.shade800 : Colors.grey.shade300,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, size: 16),
            tooltip: 'Previous Month',
            onPressed: () {
              onMonthChanged(DateTime(selectedMonth.year, selectedMonth.month - 1, 1));
            },
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_month_rounded, size: 18, color: Theme.of(context).primaryColor),
              const SizedBox(width: 8),
              Text(
                monthStr,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            tooltip: 'Next Month',
            onPressed: () {
              onMonthChanged(DateTime(selectedMonth.year, selectedMonth.month + 1, 1));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationBar({
    required int currentPage,
    required int totalPages,
    required ValueChanged<int> onPageChanged,
    required bool isDark,
  }) {
    if (totalPages <= 1) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          InkWell(
            onTap: currentPage > 1 ? () => onPageChanged(currentPage - 1) : null,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: currentPage > 1
                    ? (isDark ? const Color(0xFF1E293B) : Colors.grey.shade200)
                    : (isDark ? Colors.white10 : Colors.grey.shade100),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.chevron_left_rounded,
                size: 20,
                color: currentPage > 1 ? (isDark ? Colors.white : Colors.black87) : Colors.grey,
              ),
            ),
          ),
          const SizedBox(width: 6),
          for (int i = 1; i <= totalPages; i++) ...[
            if (totalPages <= 7 || i == 1 || i == totalPages || (i >= currentPage - 1 && i <= currentPage + 1)) ...[
              InkWell(
                onTap: () => onPageChanged(i),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: i == currentPage
                        ? Theme.of(context).primaryColor
                        : (isDark ? const Color(0xFF1E293B) : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: i == currentPage
                          ? Theme.of(context).primaryColor
                          : (isDark ? Colors.grey.shade700 : Colors.grey.shade300),
                    ),
                  ),
                  child: Text(
                    '$i',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: i == currentPage ? FontWeight.bold : FontWeight.normal,
                      color: i == currentPage ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                    ),
                  ),
                ),
              ),
            ] else if (i == 2 && currentPage > 3) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2),
                child: Text('...', style: TextStyle(color: Colors.grey)),
              ),
            ] else if (i == totalPages - 1 && currentPage < totalPages - 2) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2),
                child: Text('...', style: TextStyle(color: Colors.grey)),
              ),
            ],
          ],
          const SizedBox(width: 6),
          InkWell(
            onTap: currentPage < totalPages ? () => onPageChanged(currentPage + 1) : null,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: currentPage < totalPages
                    ? (isDark ? const Color(0xFF1E293B) : Colors.grey.shade200)
                    : (isDark ? Colors.white10 : Colors.grey.shade100),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: currentPage < totalPages ? (isDark ? Colors.white : Colors.black87) : Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // TAB 1: AUTO-APPLY AGENT TAB (10 AM & 10 PM SCHEDULER)
  // ============================================================================

  Widget _buildAutoApplyTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Scrollbar(
      controller: _autoAppScrollController,
      child: SingleChildScrollView(
        controller: _autoAppScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Banner: Schedule & Configuration health
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
                      : [const Color(0xFFEFF6FF), const Color(0xFFDBEAFE)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.blueAccent.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blueAccent.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.schedule_send_rounded, color: Colors.blueAccent, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Twice Daily Auto-Apply',
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                              ),
                              const Text(
                                'Runs every day at 10:00 AM & 10:00 PM IST',
                                style: TextStyle(fontSize: 11, color: Colors.blueAccent, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Switch.adaptive(
                        value: _autoApplyEnabled,
                        activeTrackColor: Colors.blueAccent,
                        onChanged: (val) {
                          setState(() => _autoApplyEnabled = val);
                          _service.setAutoApplyEnabled(val);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  // Health checklist: Resume & Gmail
                  Builder(
                    builder: (context) {
                      final bool hasResumeActive = _hasResume || _resumeProfiles.isNotEmpty;
                      final String displayResumeName = _resumeFileName.isNotEmpty
                          ? _resumeFileName
                          : (_resumeProfiles.isNotEmpty ? _resumeProfiles.first.fileName : 'Active');
                      final bool hasEmailConfig = _userEmail.trim().isNotEmpty && _userAppPassword.trim().isNotEmpty;

                      return Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: _showJobAssistantSettingsDialog,
                              child: Row(
                                children: [
                                  Icon(
                                    hasResumeActive ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                                    color: hasResumeActive ? const Color(0xFF10B981) : Colors.orange,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      hasResumeActive ? 'Resume: $displayResumeName' : 'Resume: Tap to upload',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w500,
                                        color: isDark ? Colors.white70 : Colors.black87,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: InkWell(
                              onTap: _showJobAssistantSettingsDialog,
                              child: Row(
                                children: [
                                  Icon(
                                    hasEmailConfig
                                        ? Icons.check_circle_rounded
                                        : Icons.warning_amber_rounded,
                                    color: hasEmailConfig
                                        ? const Color(0xFF10B981)
                                        : Colors.orange,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      hasEmailConfig
                                          ? 'Gmail: $_userEmail'
                                          : 'Gmail: Tap to set',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w500,
                                        color: isDark ? Colors.white70 : Colors.black87,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  // Last Run & Last Applied Timestamps Card
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              const Icon(Icons.history_toggle_off_rounded, color: Colors.blueAccent, size: 16),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'LAST RUN',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                        color: isDark ? Colors.white54 : Colors.grey[600],
                                      ),
                                    ),
                                    Text(
                                      _formatRelativeTimestamp(_jobsLastRan, isLastRun: true),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          height: 22,
                          width: 1,
                          color: isDark ? Colors.white12 : Colors.black12,
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              const Icon(Icons.send_rounded, color: Color(0xFF10B981), size: 15),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'LAST APPLIED',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                        color: isDark ? Colors.white54 : Colors.grey[600],
                                      ),
                                    ),
                                    Text(
                                      _formatRelativeTimestamp(_jobsLastApplied),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Search Preferences Card
            Card(
              color: cardBg,
              elevation: isDark ? 2 : 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  initiallyExpanded: false,
                  leading: const Icon(Icons.tune_rounded, color: Colors.blueAccent),
                  title: Text(
                    '🎯 Target Roles, Locations & Exp',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14.5),
                  ),
                  subtitle: Text(
                    '${_targetRolesController.text.trim().isNotEmpty ? _targetRolesController.text.trim() : "Target Roles"} • ${_locationsController.text.trim().isNotEmpty ? _locationsController.text.trim() : "Locations"} • ${_isFresher ? "Fresher (0 Yrs)" : "${_minExpController.text.trim()}-${_maxExpController.text.trim()} Yrs"}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(),
                          const SizedBox(height: 8),
                    TextField(
                      controller: _applicantNameController,
                      decoration: InputDecoration(
                        labelText: 'Your Full Name (used in applications & emails)',
                        hintText: 'e.g. Roshan J or Dhanush',
                        prefixIcon: const Icon(Icons.person_outline_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _targetRolesController,
                      decoration: InputDecoration(
                        labelText: 'Target Job Roles (comma-separated)',
                        hintText: 'e.g. .NET Developer, Software Engineer, Full Stack Developer, Flutter Developer',
                        prefixIcon: const Icon(Icons.work_outline_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        isDense: true,
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _locationsController,
                      decoration: InputDecoration(
                        labelText: 'Target Locations (comma-separated)',
                        hintText: 'e.g. Bengaluru, India, Remote, Chennai',
                        prefixIcon: const Icon(Icons.location_on_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Configurable Blacklist / Excluded Companies
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _excludedCompanies.isNotEmpty
                              ? Colors.redAccent.withValues(alpha: 0.3)
                              : (isDark ? const Color(0xFF334155) : Colors.grey.shade300),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Icon(Icons.block_rounded, color: Colors.redAccent, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Excluded Companies / Agencies (Blacklist)',
                                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (_excludedCompanies.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${_excludedCompanies.length} Excluded',
                                    style: const TextStyle(fontSize: 10.5, color: Colors.redAccent, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Auto-discovery will automatically reject and skip openings from these employers or recruitment agencies (e.g. current company or consultancy spam).',
                            style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey[600]),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _excludeCompanyController,
                                  decoration: InputDecoration(
                                    hintText: 'e.g. Current Employer, Consultancy Name...',
                                    hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                                    prefixIcon: const Icon(Icons.domain_disabled_rounded, size: 18),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  ),
                                  onSubmitted: (val) {
                                    final c = val.trim();
                                    if (c.isNotEmpty && !_excludedCompanies.contains(c)) {
                                      setState(() {
                                        _excludedCompanies.add(c);
                                        _excludeCompanyController.clear();
                                      });
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () {
                                  final c = _excludeCompanyController.text.trim();
                                  if (c.isNotEmpty && !_excludedCompanies.contains(c)) {
                                    setState(() {
                                      _excludedCompanies.add(c);
                                      _excludeCompanyController.clear();
                                    });
                                  }
                                },
                                child: const Text('+ Add', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_excludedCompanies.isNotEmpty)
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: _excludedCompanies.map((comp) {
                                return Chip(
                                  backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                                  side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3)),
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  avatar: const Icon(Icons.block, size: 14, color: Colors.redAccent),
                                  label: Text(comp, style: const TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                  deleteIcon: const Icon(Icons.close_rounded, size: 14, color: Colors.redAccent),
                                  onDeleted: () {
                                    setState(() {
                                      _excludedCompanies.remove(comp);
                                    });
                                  },
                                );
                              }).toList(),
                            )
                          else
                            Text(
                              'No companies excluded yet. Add your current employer or consultancy names to filter out.',
                              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey.shade500),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Fresher Checkbox Toggle
                    Container(
                      decoration: BoxDecoration(
                        color: _isFresher ? Colors.blue.withValues(alpha: 0.12) : Colors.grey.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _isFresher ? Colors.blue.withValues(alpha: 0.4) : Colors.grey.withValues(alpha: 0.2),
                        ),
                      ),
                      child: CheckboxListTile(
                        value: _isFresher,
                        activeColor: Colors.blue,
                        title: Text('I am a Fresher (0 Years Experience)', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text(
                          _isFresher
                              ? 'Targeting Freshers / Entry-Level / 0 Yrs roles'
                              : 'Check if you are seeking entry-level/fresher job openings',
                          style: TextStyle(fontSize: 11, color: _isFresher ? Colors.blue.shade800 : Colors.grey),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        onChanged: (val) {
                          setState(() {
                            _isFresher = val ?? false;
                            if (_isFresher) {
                              _minExpController.text = '0';
                              _maxExpController.text = '0';
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Configurable Experience Range (Hidden if Fresher)
                    if (!_isFresher)
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _minExpController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Min Exp (Years)',
                                hintText: '0',
                                prefixIcon: const Icon(Icons.timeline_rounded),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                isDense: true,
                              ),
                              onChanged: (_) {
                                setState(() {});
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _maxExpController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Max Exp (Years)',
                                hintText: '3',
                                prefixIcon: const Icon(Icons.timeline_rounded),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                isDense: true,
                              ),
                              onChanged: (_) {
                                setState(() {});
                              },
                            ),
                          ),
                        ],
                      ),
                    if (!_isFresher) const SizedBox(height: 14),
                    if (_isFresher) const SizedBox(height: 4),
                    // Filter Badges
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.teal.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.filter_alt_rounded, color: Colors.teal, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                _isFresher
                                    ? 'Experience: Fresher / Entry-Level (0 Yrs)'
                                    : 'Experience: ${_minExpController.text.trim().isEmpty ? '0' : _minExpController.text.trim()} – ${_maxExpController.text.trim().isEmpty ? '3' : _maxExpController.text.trim()} Years',
                                style: const TextStyle(fontSize: 11, color: Colors.teal, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.mark_email_read_rounded, color: Colors.purple, size: 14),
                              SizedBox(width: 4),
                              Text('Verified Recruiter Emails Only', style: TextStyle(fontSize: 11, color: Colors.purple, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.attachment_rounded, color: Colors.amber, size: 14),
                              SizedBox(width: 4),
                              Text('Attached Resume PDF', style: TextStyle(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        if (_excludedCompanies.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.block_rounded, color: Colors.redAccent, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  '${_excludedCompanies.length} Blacklisted',
                                  style: const TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Dedicated In-Card Save Button
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton.icon(
                        onPressed: _isSavingAutoSettings ? null : _saveAutoApplySettings,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        icon: _isSavingAutoSettings
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save_rounded, size: 18),
                        label: Text(
                          _isSavingAutoSettings ? 'Saving Settings...' : '💾 Save Target Preferences',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // On-Demand Auto-Apply
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 3,
                ),
                onPressed: _isRunningAutoApply ? null : _runAutoApplyNow,
                icon: _isRunningAutoApply
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.rocket_launch_rounded, size: 20),
                label: Text(
                  _isRunningAutoApply ? 'Applying to Matching Openings...' : '🚀 Run Auto-Apply Now',
                  style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.bold),
                ),
              ),
            ),

            if (_autoApplyStatusMessage.isNotEmpty) ...[
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _autoApplyStatusMessage,
                  style: const TextStyle(fontSize: 11.5, color: Colors.blueAccent, fontStyle: FontStyle.italic),
                  textAlign: TextAlign.center,
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Recent Auto-Applied Applications Section (Filtered for isAutoApplied == true ONLY)
            // Automated Applications Section with Monthly View & Pagination
            Text(
              '📬 Automated Applications',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 6),
            _buildMonthSelector(
              selectedMonth: _autoApplyMonth,
              onMonthChanged: (m) => setState(() {
                _autoApplyMonth = m;
                _autoApplyPage = 1;
              }),
              isDark: isDark,
            ),
            const SizedBox(height: 10),

            StreamBuilder<List<JobApplication>>(
              initialData: _service.cachedApplications,
              stream: _applicationsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
                }

                final allApps = snapshot.data ?? [];
                // Filter for isAutoApplied == true AND matching selected month & year
                final monthApps = allApps.where((a) =>
                    a.isAutoApplied &&
                    a.appliedAt.year == _autoApplyMonth.year &&
                    a.appliedAt.month == _autoApplyMonth.month
                ).toList();

                // Sort latest first
                monthApps.sort((a, b) => b.appliedAt.compareTo(a.appliedAt));

                if (monthApps.isEmpty) {
                  return Card(
                    color: cardBg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        children: [
                          Icon(Icons.work_outline_rounded, size: 40, color: Colors.grey.shade400),
                          const SizedBox(height: 10),
                          Text(
                            'No Applications in ${DateFormat('MMMM yyyy').format(_autoApplyMonth)}',
                            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'The agent runs automatically at 10:00 AM & 10:00 PM IST, or you can tap "Run Auto-Discovery & Apply Now" anytime!',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final totalPages = (monthApps.length / 10).ceil();
                final safePage = _autoApplyPage.clamp(1, totalPages);
                final startIndex = (safePage - 1) * 10;
                final displayedApps = monthApps.skip(startIndex).take(10).toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: displayedApps.length,
                      itemBuilder: (context, index) {
                        final app = displayedApps[index];
                        return _buildAutoAppCard(app, isDark);
                      },
                    ),
                    _buildPaginationBar(
                      currentPage: safePage,
                      totalPages: totalPages,
                      onPageChanged: (p) => setState(() => _autoApplyPage = p),
                      isDark: isDark,
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? Colors.blue.shade900.withValues(alpha: 0.5) : Colors.blue.shade200,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.assessment_outlined,
                                size: 18,
                                color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'In ${DateFormat('MMM yyyy').format(_autoApplyMonth)}: ${monthApps.length} (Page $safePage of $totalPages)',
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: isDark ? Colors.blue.shade200 : Colors.blue.shade900,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.blue.shade800 : Colors.blue.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${allApps.where((a) => a.isAutoApplied).length} Total Sent',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: isDark ? Colors.white : Colors.blue.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoAppCard(JobApplication app, bool isDark) {
    final String source = (app.sourcePlatform != null && app.sourcePlatform!.isNotEmpty)
        ? app.sourcePlatform!
        : 'LinkedIn';

    final bool isBounced = app.isBounced || app.status == 'bounced' || app.responseType == 'bounced';
    final bool hasReplied = app.status == 'reply_received' || (app.responseType != null && app.responseType!.isNotEmpty && !isBounced);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isBounced
            ? BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.4), width: 1)
            : BorderSide.none,
      ),
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      elevation: 1.5,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: isBounced
              ? const Color(0xFFEF4444).withValues(alpha: 0.18)
              : (hasReplied
                  ? const Color(0xFF10B981).withValues(alpha: 0.2)
                  : Colors.blueAccent.withValues(alpha: 0.15)),
          child: Icon(
            isBounced
                ? Icons.error_outline_rounded
                : (hasReplied
                    ? Icons.mark_email_unread_rounded
                    : Icons.send_rounded),
            color: isBounced
                ? const Color(0xFFEF4444)
                : (hasReplied
                    ? const Color(0xFF10B981)
                    : Colors.blueAccent),
            size: 18,
          ),
        ),
        title: Text(
          app.jobTitle,
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              '${app.companyName} • ${app.recipientEmail}',
              style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white70 : Colors.grey[700]),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (isBounced)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.45)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline_rounded, size: 10, color: Color(0xFFEF4444)),
                        SizedBox(width: 3),
                        Text(
                          'Address Not Found',
                          style: TextStyle(fontSize: 9.5, color: Color(0xFFEF4444), fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  )
                else if (hasReplied)
                  _buildResponseBadge(app, isDark)
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.picture_as_pdf_rounded, size: 10, color: Color(0xFF10B981)),
                        const SizedBox(width: 3),
                        Text(
                          app.resumeProfileName != null && app.resumeProfileName!.isNotEmpty
                              ? 'Profile: ${app.resumeProfileName}'
                              : 'Sent with Resume PDF',
                          style: const TextStyle(fontSize: 9.5, color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.language_rounded, size: 10, color: Colors.indigoAccent),
                      const SizedBox(width: 3),
                      Text('Source: $source', style: const TextStyle(fontSize: 9.5, color: Colors.indigoAccent, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                if (app.modelUsed != null && app.modelUsed!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.psychology_rounded, size: 10, color: Colors.purpleAccent),
                        const SizedBox(width: 3),
                        Text('AI: ${app.modelUsed}', style: const TextStyle(fontSize: 9.5, color: Colors.purpleAccent, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                Text(
                  '${app.appliedAt.day}/${app.appliedAt.month} ${app.appliedAt.hour.toString().padLeft(2, '0')}:${app.appliedAt.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 10, color: isDark ? Colors.white54 : Colors.grey[500]),
                ),
              ],
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isBounced || hasReplied)
                  _buildRecruiterReplyCard(app, isDark),
                Text(
                  'Sent Application Subject: ${app.generatedSubject}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    app.generatedCoverLetter,
                    style: TextStyle(fontSize: 11.5, height: 1.4, color: isDark ? Colors.white70 : Colors.black87),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // TAB: LINKEDIN POSTS AUTO-APPLY (APIFY REAL-TIME RECRUITER POSTS)
  // ============================================================================

  Future<void> _triggerLinkedInAutoApplyNow() async {
    if (_isRunningLinkedInAutoApply) return;
    setState(() {
      _isRunningLinkedInAutoApply = true;
      _linkedInAutoApplyStatusMessage = 'Scraping real-time LinkedIn recruiter posts via Apify...';
    });

    try {
      final roles = _linkedInRolesController.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final minExp = int.tryParse(_linkedInMinExpController.text.trim()) ?? 1;
      final maxExp = int.tryParse(_linkedInMaxExpController.text.trim()) ?? 3;

      final res = await _service.runLinkedInAutoApplyNow(
        roles: roles.isNotEmpty ? roles : null,
        minExpYears: minExp,
        maxExpYears: maxExp,
      );

      final success = res['success'] == true;
      final count = res['appliedCount'] ?? 0;
      final msg = res['message'] ?? 'Run completed.';

      if (mounted) {
        setState(() {
          _isRunningLinkedInAutoApply = false;
          _linkedInAutoApplyStatusMessage = msg;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? '⚡ $msg' : '⚠️ $msg'),
            backgroundColor: success ? (count > 0 ? Colors.green : Colors.blueGrey) : Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRunningLinkedInAutoApply = false;
          _linkedInAutoApplyStatusMessage = 'Error: $e';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to run LinkedIn Auto-Apply: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showLinkedInSettingsDialog() {
    bool obscureT1 = true;
    bool obscureT2 = true;
    bool obscureT3 = true;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A66C2).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.settings_suggest_rounded, color: Color(0xFF0A66C2)),
                ),
                const SizedBox(width: 10),
                Text(
                  'LinkedIn Auto-Apply Settings',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17),
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A66C2).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF0A66C2).withValues(alpha: 0.2)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded, color: Color(0xFF0A66C2), size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Configure up to 3 Apify API Tokens. The system cycles across accounts to prevent exhausting free tier quotas, without retrying failed tokens to preserve credits.',
                              style: TextStyle(fontSize: 12, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Apify API Tokens', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 8),
                    // Token 1
                    TextField(
                      controller: _apifyToken1Controller,
                      obscureText: obscureT1,
                      decoration: InputDecoration(
                        labelText: 'Token 1 (Primary) *',
                        hintText: 'apify_api_...',
                        prefixIcon: const Icon(Icons.key_rounded, size: 18),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(obscureT1 ? Icons.visibility_off : Icons.visibility, size: 18),
                              onPressed: () => setDlgState(() => obscureT1 = !obscureT1),
                            ),
                            IconButton(
                              icon: const Icon(Icons.paste_rounded, size: 18),
                              tooltip: 'Paste from clipboard',
                              onPressed: () async {
                                final data = await Clipboard.getData('text/plain');
                                if (data?.text != null) {
                                  _apifyToken1Controller.text = data!.text!.trim();
                                  setDlgState(() {});
                                }
                              },
                            ),
                          ],
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Token 2
                    TextField(
                      controller: _apifyToken2Controller,
                      obscureText: obscureT2,
                      decoration: InputDecoration(
                        labelText: 'Token 2 (Backup)',
                        hintText: 'apify_api_... (optional)',
                        prefixIcon: const Icon(Icons.key_rounded, size: 18),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(obscureT2 ? Icons.visibility_off : Icons.visibility, size: 18),
                              onPressed: () => setDlgState(() => obscureT2 = !obscureT2),
                            ),
                            IconButton(
                              icon: const Icon(Icons.paste_rounded, size: 18),
                              tooltip: 'Paste from clipboard',
                              onPressed: () async {
                                final data = await Clipboard.getData('text/plain');
                                if (data?.text != null) {
                                  _apifyToken2Controller.text = data!.text!.trim();
                                  setDlgState(() {});
                                }
                              },
                            ),
                          ],
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Token 3
                    TextField(
                      controller: _apifyToken3Controller,
                      obscureText: obscureT3,
                      decoration: InputDecoration(
                        labelText: 'Token 3 (Backup)',
                        hintText: 'apify_api_... (optional)',
                        prefixIcon: const Icon(Icons.key_rounded, size: 18),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(obscureT3 ? Icons.visibility_off : Icons.visibility, size: 18),
                              onPressed: () => setDlgState(() => obscureT3 = !obscureT3),
                            ),
                            IconButton(
                              icon: const Icon(Icons.paste_rounded, size: 18),
                              tooltip: 'Paste from clipboard',
                              onPressed: () async {
                                final data = await Clipboard.getData('text/plain');
                                if (data?.text != null) {
                                  _apifyToken3Controller.text = data!.text!.trim();
                                  setDlgState(() {});
                                }
                              },
                            ),
                          ],
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Target Job Roles (comma-separated)', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _linkedInRolesController,
                      decoration: InputDecoration(
                        hintText: 'e.g. DevOps Engineer, Cloud Engineer, Site Reliability Engineer',
                        prefixIcon: const Icon(Icons.work_outline_rounded, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Experience Range (Years)', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _linkedInMinExpController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Min Years',
                              prefixIcon: const Icon(Icons.timer_outlined, size: 18),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _linkedInMaxExpController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Max Years',
                              prefixIcon: const Icon(Icons.timer_rounded, size: 18),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isSaving ? null : () async {
                  setDlgState(() => isSaving = true);
                  final roles = _linkedInRolesController.text
                      .split(',')
                      .map((s) => s.trim())
                      .where((s) => s.isNotEmpty)
                      .toList();
                  final minExp = int.tryParse(_linkedInMinExpController.text.trim()) ?? 1;
                  final maxExp = int.tryParse(_linkedInMaxExpController.text.trim()) ?? 3;

                  final tokens = [
                    _apifyToken1Controller.text.trim(),
                    _apifyToken2Controller.text.trim(),
                    _apifyToken3Controller.text.trim(),
                  ].where((t) => t.isNotEmpty).toList();

                  await _service.saveLinkedInAutoApplySettings({
                    'apifyToken1': _apifyToken1Controller.text.trim(),
                    'apifyToken2': _apifyToken2Controller.text.trim(),
                    'apifyToken3': _apifyToken3Controller.text.trim(),
                    'apifyTokens': tokens,
                    'targetRoles': roles,
                    'minExpYears': minExp,
                    'maxExpYears': maxExp,
                    'enabled': _linkedInAutoApplyEnabled,
                    'updatedAt': FieldValue.serverTimestamp(),
                  });

                  if (context.mounted) {
                    Navigator.pop(dlgCtx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('LinkedIn Auto-Apply settings saved successfully!'),
                        backgroundColor: Colors.green,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    setState(() {});
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0A66C2),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Settings'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLinkedInPostsTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;

    // 1. Admin Module Control: If disabled by admin, display locked banner
    if (!_isLinkedInAutoApplyModuleEnabled) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3), width: 2),
                ),
                child: const Icon(Icons.lock_person_rounded, size: 54, color: Colors.amber),
              ),
              const SizedBox(height: 20),
              Text(
                'LinkedIn Auto-Apply Disabled',
                style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'This module is currently disabled by the administrator for your account.\n\nTo activate real-time LinkedIn recruiter post scraping & auto-apply, please request your administrator to enable "LinkedIn Auto-Apply" for your username in the Admin Panel.',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey[400] : Colors.grey[700],
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Contact your administrator to enable LinkedIn Auto-Apply in the Admin Console.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: const Icon(Icons.info_outline_rounded, size: 18),
                label: const Text('Admin Activation Required'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.amber,
                  side: const BorderSide(color: Colors.amber),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Count configured tokens
    final configuredTokensCount = [
      _apifyToken1Controller.text.trim(),
      _apifyToken2Controller.text.trim(),
      _apifyToken3Controller.text.trim(),
    ].where((t) => t.isNotEmpty).length;

    return Scrollbar(
      controller: _linkedInScrollController,
      child: SingleChildScrollView(
        controller: _linkedInScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Banner: LinkedIn Scraper & Schedule health
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF0F1E36), const Color(0xFF1E293B)]
                      : [const Color(0xFFE8F3FF), const Color(0xFFD0E7FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF0A66C2).withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0A66C2).withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.dynamic_feed_rounded, color: Color(0xFF0A66C2), size: 22),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'LinkedIn Recruiter Post Scraper',
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                              ),
                              const Text(
                                'Runs every day at 10:30 AM & 8:30 PM IST (Asia/Kolkata)',
                                style: TextStyle(fontSize: 11, color: Color(0xFF0A66C2), fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Switch.adaptive(
                        value: _linkedInAutoApplyEnabled,
                        activeTrackColor: const Color(0xFF0A66C2),
                        onChanged: (val) {
                          setState(() => _linkedInAutoApplyEnabled = val);
                          _service.saveLinkedInAutoApplySettings({
                            'enabled': val,
                            'updatedAt': FieldValue.serverTimestamp(),
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Directly extracts real-time hiring posts published in the past 24h with recruiter emails via residential Apify scrapers. Deduplicates against your Unified Applied Job History, validates experience with Gemini, and auto-applies via Gmail.',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[300] : const Color(0xFF334155),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  // Health checklist: Resume, Gmail & Apify Tokens
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      // Resume status
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _hasResume ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                            size: 16,
                            color: _hasResume ? Colors.green : Colors.amber,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _hasResume ? 'Resume PDF Ready' : 'No Resume Uploaded',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _hasResume ? Colors.green : Colors.amber,
                            ),
                          ),
                        ],
                      ),
                      // Gmail config
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _userEmail.isNotEmpty && _userAppPassword.isNotEmpty
                                ? Icons.check_circle_rounded
                                : Icons.warning_amber_rounded,
                            size: 16,
                            color: _userEmail.isNotEmpty && _userAppPassword.isNotEmpty ? Colors.green : Colors.amber,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _userEmail.isNotEmpty && _userAppPassword.isNotEmpty
                                ? 'Gmail Connected ($_userEmail)'
                                : 'Gmail App Password Missing',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _userEmail.isNotEmpty && _userAppPassword.isNotEmpty ? Colors.green : Colors.amber,
                            ),
                          ),
                        ],
                      ),
                      // Apify Tokens
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            configuredTokensCount > 0 ? Icons.key_rounded : Icons.vpn_key_off_rounded,
                            size: 16,
                            color: configuredTokensCount > 0 ? const Color(0xFF0A66C2) : Colors.amber,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            configuredTokensCount > 0
                                ? '$configuredTokensCount/3 Apify Tokens Active'
                                : 'Default Token Active (Add yours in Settings)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: configuredTokensCount > 0 ? const Color(0xFF0A66C2) : Colors.amber,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (_linkedInLastRan != null || _linkedInLastApplied != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (_linkedInLastRan != null)
                          Text(
                            'Last scan: ${DateFormat('dd MMM, hh:mm a').format(_linkedInLastRan!)}',
                            style: TextStyle(fontSize: 11, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                          ),
                        if (_linkedInLastRan != null && _linkedInLastApplied != null)
                          Text(' • ', style: TextStyle(fontSize: 11, color: isDark ? Colors.grey[500] : Colors.grey[400])),
                        if (_linkedInLastApplied != null)
                          Text(
                            'Last applied: ${DateFormat('dd MMM, hh:mm a').format(_linkedInLastApplied!)}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  // Action buttons
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _isRunningLinkedInAutoApply ? null : _triggerLinkedInAutoApplyNow,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0A66C2),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        icon: _isRunningLinkedInAutoApply
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.bolt_rounded, size: 18),
                        label: Text(
                          _isRunningLinkedInAutoApply ? 'Scraping & Applying...' : 'Run Search & Apply Now',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: _showLinkedInSettingsDialog,
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                        icon: const Icon(Icons.tune_rounded, size: 18),
                        label: const Text('Settings & 3 Tokens'),
                      ),
                    ],
                  ),
                  if (_isRunningLinkedInAutoApply || _linkedInAutoApplyStatusMessage.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    if (_isRunningLinkedInAutoApply)
                      const LinearProgressIndicator(
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0A66C2)),
                      ),
                    if (_linkedInAutoApplyStatusMessage.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _linkedInAutoApplyStatusMessage,
                          style: TextStyle(fontSize: 11.5, color: isDark ? Colors.blue[200] : const Color(0xFF0A66C2), fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Month Selector
            _buildMonthSelector(
              selectedMonth: _linkedInMonth,
              onMonthChanged: (newMonth) {
                setState(() {
                  _linkedInMonth = newMonth;
                  _linkedInPage = 1;
                });
              },
              isDark: isDark,
            ),

            const SizedBox(height: 12),

            // Real-Time Applications List from Unified job_applications collection
            StreamBuilder<List<JobApplication>>(
              initialData: _service.cachedApplications,
              stream: _applicationsStream,
              builder: (context, snapshot) {
                final allApps = snapshot.data ?? [];
                // Filter for LinkedIn Posts from Apify
                final linkedInApps = allApps.where((a) {
                  final isLinkedIn = a.sourcePlatform?.contains('LinkedIn Post') == true ||
                      a.sourcePlatform?.contains('Apify') == true ||
                      a.source == 'linkedin_post_apify';
                  final matchesMonth = a.appliedAt.year == _linkedInMonth.year && a.appliedAt.month == _linkedInMonth.month;
                  return isLinkedIn && matchesMonth;
                }).toList();

                if (linkedInApps.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(32),
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0A66C2).withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.mark_email_read_outlined, size: 40, color: Color(0xFF0A66C2)),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No LinkedIn Post Applications Sent for ${DateFormat('MMMM yyyy').format(_linkedInMonth)}',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Click "Run Search & Apply Now" above or wait for the scheduled morning (10:30 AM IST) & evening (8:30 PM IST) runs.',
                          style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                // Numbered pagination: 10 per page
                const pageSize = 10;
                final totalPages = (linkedInApps.length / pageSize).ceil();
                final safePage = _linkedInPage.clamp(1, totalPages > 0 ? totalPages : 1);
                final startIndex = (safePage - 1) * pageSize;
                final endIndex = (startIndex + pageSize) > linkedInApps.length ? linkedInApps.length : (startIndex + pageSize);
                final pagedApps = linkedInApps.sublist(startIndex, endIndex);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${linkedInApps.length} LinkedIn Post Application${linkedInApps.length > 1 ? 's' : ''} in ${DateFormat('MMMM yyyy').format(_linkedInMonth)}',
                          style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        if (totalPages > 1)
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.chevron_left_rounded),
                                onPressed: safePage > 1 ? () => setState(() => _linkedInPage = safePage - 1) : null,
                              ),
                              Text('Page $safePage of $totalPages', style: const TextStyle(fontSize: 12)),
                              IconButton(
                                icon: const Icon(Icons.chevron_right_rounded),
                                onPressed: safePage < totalPages ? () => setState(() => _linkedInPage = safePage + 1) : null,
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ...pagedApps.map((app) => _buildLinkedInApplicationCard(app, isDark)),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinkedInApplicationCard(JobApplication app, bool isDark) {
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF0A66C2).withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0A66C2).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.dynamic_feed_rounded, color: Color(0xFF0A66C2), size: 24),
          ),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.jobTitle,
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      app.companyName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.blue[200] : const Color(0xFF0A66C2),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded, size: 12, color: Colors.green),
                    SizedBox(width: 4),
                    Text(
                      'Sent via Apify',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                  ],
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                // Recruiter email
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.email_outlined, size: 13, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      app.recipientEmail,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: app.recipientEmail));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Copied ${app.recipientEmail} to clipboard!'),
                            duration: const Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      child: const Icon(Icons.copy_rounded, size: 13, color: Colors.grey),
                    ),
                  ],
                ),
                // Applied time
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.access_time_rounded, size: 13, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('dd MMM, hh:mm a').format(app.appliedAt),
                      style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                    ),
                  ],
                ),
                // Resume profile name
                if (app.resumeProfileName != null && app.resumeProfileName!.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.picture_as_pdf_rounded, size: 13, color: Color(0xFF10B981)),
                      const SizedBox(width: 4),
                      Text(
                        app.resumeProfileName!,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          children: [
            const Divider(height: 16),
            if (app.authorName != null && app.authorName!.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.person_outline_rounded, size: 15, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                    'Post Author: ${app.authorName}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (app.sourceUrl != null && app.sourceUrl!.isNotEmpty)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.open_in_new_rounded, size: 13, color: Color(0xFF0A66C2)),
                      label: const Text('View LinkedIn Post', style: TextStyle(fontSize: 11, color: Color(0xFF0A66C2))),
                      onPressed: () => UrlLauncherHelper.openInNewTabOrExternal(app.sourceUrl!),
                    ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            if (app.postExcerpt != null && app.postExcerpt!.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black26 : Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isDark ? Colors.white12 : Colors.grey[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('LinkedIn Post Excerpt:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Text(
                      app.postExcerpt!,
                      style: const TextStyle(fontSize: 11.5, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            // Cover Letter
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Tailored Application Email Sent:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.copy_rounded, size: 13),
                  label: const Text('Copy Email', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: 'Subject: ${app.generatedSubject}\n\n${app.generatedCoverLetter}'));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Email copied to clipboard!'),
                        duration: Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Subject: ${app.generatedSubject}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    app.generatedCoverLetter,
                    style: const TextStyle(fontSize: 12, height: 1.45),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // TAB 1: NEW APPLICATION TAB
  // ============================================================================

  Widget _buildNewApplicationTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Scrollbar(
      controller: _newAppScrollController,
      child: SingleChildScrollView(
        controller: _newAppScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Master Resume Info Bar (Linked to Settings)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _hasResume
                    ? (isDark ? const Color(0xFF064E3B).withValues(alpha: 0.4) : const Color(0xFFECFDF5))
                    : (isDark ? const Color(0xFF78350F).withValues(alpha: 0.4) : const Color(0xFFFFFBEB)),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _hasResume
                      ? const Color(0xFF10B981).withValues(alpha: 0.4)
                      : Colors.orange.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _hasResume ? Icons.picture_as_pdf_rounded : Icons.upload_file_rounded,
                    color: _hasResume ? const Color(0xFF10B981) : Colors.orange,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _hasResume ? 'Master Resume: $_resumeFileName' : 'No Resume Uploaded',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _hasResume ? 'Attached & analyzed automatically' : 'Upload your resume in Settings',
                          style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    ),
                    onPressed: _showJobAssistantSettingsDialog,
                    icon: const Icon(Icons.settings, size: 14),
                    label: Text(_hasResume ? 'Settings' : 'Upload in Settings', style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Upload Mode Choice
            Text('Upload Mode Strategy:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text(
                    '📄 1 Job (Multi-page Screenshot)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: _uploadMode == 'single_job' ? FontWeight.bold : FontWeight.normal,
                      color: _uploadMode == 'single_job'
                          ? (isDark ? Colors.blue.shade200 : Colors.blue.shade900)
                          : (isDark ? Colors.grey.shade300 : Colors.grey.shade800),
                    ),
                  ),
                  selected: _uploadMode == 'single_job',
                  selectedColor: isDark ? const Color(0xFF1E3A8A) : Colors.blue.shade100,
                  backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
                  side: BorderSide(
                    color: _uploadMode == 'single_job'
                        ? (isDark ? Colors.blueAccent : Colors.blue)
                        : (isDark ? const Color(0xFF334155) : Colors.grey.shade300),
                  ),
                  onSelected: (val) {
                    if (val) setState(() => _uploadMode = 'single_job');
                  },
                ),
                ChoiceChip(
                  label: Text(
                    '📁 Multiple Separate Screenshots',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: _uploadMode == 'multiple_jobs' ? FontWeight.bold : FontWeight.normal,
                      color: _uploadMode == 'multiple_jobs'
                          ? (isDark ? Colors.blue.shade200 : Colors.blue.shade900)
                          : (isDark ? Colors.grey.shade300 : Colors.grey.shade800),
                    ),
                  ),
                  selected: _uploadMode == 'multiple_jobs',
                  selectedColor: isDark ? const Color(0xFF1E3A8A) : Colors.blue.shade100,
                  backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
                  side: BorderSide(
                    color: _uploadMode == 'multiple_jobs'
                        ? (isDark ? Colors.blueAccent : Colors.blue)
                        : (isDark ? const Color(0xFF334155) : Colors.grey.shade300),
                  ),
                  onSelected: (val) {
                    if (val) setState(() => _uploadMode = 'multiple_jobs');
                  },
                ),
                ChoiceChip(
                  label: Text(
                    '✍️ Manual / Website URL (No Screenshot)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: _uploadMode == 'manual_url' ? FontWeight.bold : FontWeight.normal,
                      color: _uploadMode == 'manual_url'
                          ? (isDark ? Colors.purple.shade200 : Colors.purple.shade900)
                          : (isDark ? Colors.grey.shade300 : Colors.grey.shade800),
                    ),
                  ),
                  selected: _uploadMode == 'manual_url',
                  selectedColor: isDark ? const Color(0xFF581C87) : Colors.purple.shade100,
                  backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
                  side: BorderSide(
                    color: _uploadMode == 'manual_url'
                        ? (isDark ? Colors.purpleAccent : Colors.purple)
                        : (isDark ? const Color(0xFF334155) : Colors.grey.shade300),
                  ),
                  onSelected: (val) {
                    if (val) setState(() => _uploadMode = 'manual_url');
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Mode View Content
            if (_uploadMode == 'manual_url') ...[
              _buildManualJobEntryForm(),
            ] else ...[
              // Pick Poster Screenshots Button / Drag & Drop / Paste Area
              CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.keyV, control: true): _pasteImageFromClipboard,
                  const SingleActivator(LogicalKeyboardKey.keyV, meta: true): _pasteImageFromClipboard,
                },
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: Colors.indigoAccent.withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18.0),
                    child: Column(
                      children: [
                        if (_selectedImageFiles.isEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.indigoAccent.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.add_photo_alternate_rounded, size: 40, color: Colors.indigoAccent),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Select, Drop, or Paste Job Poster Image(s)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Drag & drop images here, or right-click any job image in LinkedIn -> "Copy Image" and press Ctrl+V',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 12,
                            runSpacing: 10,
                            children: [
                              ElevatedButton.icon(
                                onPressed: _pickJobPosters,
                                icon: const Icon(Icons.photo_library),
                                label: const Text('Browse Files'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _pasteImageFromClipboard,
                                icon: const Icon(Icons.content_paste_rounded),
                                label: const Text('Paste Copied Image (Ctrl+V)'),
                              ),
                            ],
                          ),
                        ] else ...[
                        _buildSelectedImagesPreview(),
                        const SizedBox(height: 14),

                        // Optional Custom AI Prompt for Screenshots
                        TextFormField(
                          controller: _customScreenshotPromptController,
                          decoration: const InputDecoration(
                            labelText: 'Custom AI Instruction for Screenshots (Optional)',
                            hintText: "e.g., 'Focus only on the DevOps role in image 2', 'Ignore junior roles'",
                            prefixIcon: Icon(Icons.tune, size: 20),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          style: const TextStyle(fontSize: 12.5),
                        ),
                        const SizedBox(height: 14),

                        // Direct Auto-Send (Process in Background) Toggle
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: _autoSendInBackground
                                ? const Color(0xFF10B981).withValues(alpha: 0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _autoSendInBackground
                                  ? const Color(0xFF10B981).withValues(alpha: 0.4)
                                  : Colors.grey.withValues(alpha: 0.25),
                            ),
                          ),
                          child: SwitchListTile.adaptive(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              '⚡ Direct Auto-Send (Process in Background)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            subtitle: const Text(
                              'Auto-generate & email without manual review. 30s delay protects your Gmail account.',
                              style: TextStyle(fontSize: 11),
                            ),
                            value: _autoSendInBackground,
                            activeTrackColor: const Color(0xFF10B981),
                            onChanged: (val) {
                              setState(() => _autoSendInBackground = val);
                            },
                          ),
                        ),
                        const SizedBox(height: 14),

                        if (_selectedImageFiles.isNotEmpty)
                          Column(
                            children: [
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 10,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: _pickJobPosters,
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add File'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _pasteImageFromClipboard,
                                    icon: const Icon(Icons.content_paste_rounded),
                                    label: const Text('Paste (Ctrl+V)'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _autoSendInBackground ? const Color(0xFF10B981) : Colors.amber.shade700,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: _isAnalyzing
                                      ? null
                                      : (_autoSendInBackground ? _startAutoApplyInBackground : _analyzePostersWithAI),
                                  icon: _isAnalyzing
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : Icon(_autoSendInBackground ? Icons.send_rounded : Icons.lightbulb_outline, size: 18),
                                  label: Text(
                                    _isAnalyzing
                                        ? 'Analyzing with AI...'
                                        : (_autoSendInBackground ? '⚡ Auto-Apply in Background' : 'Analyze with Gemini AI'),
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
            const SizedBox(height: 20),

            // Extracted Job Application Cards
            if (_extractedJobs.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Extracted Applications (${_extractedJobs.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isSendingAll ? null : _sendAllEmails,
                    icon: _isSendingAll
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded, size: 16),
                    label: Text(_isSendingAll ? 'Sending All...' : 'SEND ALL (${_extractedJobs.length})'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _isSendingAll ? null : () => setState(() => _extractedJobs.clear()),
                    child: const Text('Clear All'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Column(
                children: List.generate(
                  _extractedJobs.length,
                  (index) => _buildExtractedJobCard(_extractedJobs[index], index),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildManualJobEntryForm() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < 600;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
        final inputBg = isDark ? const Color(0xFF0F172A) : Colors.white;

        InputDecoration buildInputDecoration(String label, {String? hint, Widget? prefixIcon}) {
          return InputDecoration(
            labelText: label,
            hintText: hint,
            prefixIcon: prefixIcon,
            filled: true,
            fillColor: inputBg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
            ),
            isDense: true,
          );
        }

        Widget companyAndRoleRow = isMobile
            ? Column(
                children: [
                  TextFormField(
                    controller: _manualCompanyNameController,
                    decoration: buildInputDecoration('Company Name *', prefixIcon: const Icon(Icons.business, size: 20)),
                    style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _manualJobTitleController,
                    decoration: buildInputDecoration('Job Role / Title *', prefixIcon: const Icon(Icons.work_outline, size: 20)),
                    style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _manualCompanyNameController,
                      decoration: buildInputDecoration('Company Name *', prefixIcon: const Icon(Icons.business, size: 20)),
                      style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _manualJobTitleController,
                      decoration: buildInputDecoration('Job Role / Title *', prefixIcon: const Icon(Icons.work_outline, size: 20)),
                      style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                ],
              );

        Widget urlAndEmailRow = isMobile
            ? Column(
                children: [
                  TextFormField(
                    controller: _manualCompanyUrlController,
                    decoration: buildInputDecoration('Company Website URL (Optional)', hint: 'https://company.com', prefixIcon: const Icon(Icons.link, size: 20)),
                    style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _manualRecipientEmailsController,
                    decoration: buildInputDecoration('HR Email ID(s) (Optional)', hint: 'careers@company.com, hr@company.com', prefixIcon: const Icon(Icons.email_outlined, size: 20)),
                    style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _manualCompanyUrlController,
                      decoration: buildInputDecoration('Company Website URL (Optional)', hint: 'https://company.com', prefixIcon: const Icon(Icons.link, size: 20)),
                      style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _manualRecipientEmailsController,
                      decoration: buildInputDecoration('HR Email ID(s) (Optional)', hint: 'careers@company.com, hr@company.com', prefixIcon: const Icon(Icons.email_outlined, size: 20)),
                      style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                ],
              );

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.purple.shade300, width: 1),
          ),
          color: cardBg,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.language, color: Colors.purple.shade800),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Manual / Website URL Job Application Entry',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.purple.shade900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'No screenshot required. Enter company details, website URL, and role to auto-generate a tailored cover letter with Gemini AI.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const Divider(height: 24),
                companyAndRoleRow,
                const SizedBox(height: 12),
                urlAndEmailRow,
                const SizedBox(height: 12),

                // Company Context / Notes
                TextFormField(
                  controller: _manualCompanyNotesController,
                  maxLines: 2,
                  decoration: buildInputDecoration('Company / Job Notes & Context (Optional)', hint: "e.g., 'Cloud Infrastructure consultancy looking for AWS DevOps Lead'"),
                  style: TextStyle(fontSize: 12.5, color: isDark ? Colors.white : Colors.black87),
                ),
                const SizedBox(height: 12),

                // Custom AI Instructions
                TextFormField(
                  controller: _manualCustomPromptController,
                  decoration: buildInputDecoration('Custom AI Instructions (Optional)', hint: "e.g., 'Emphasize my AWS certification & Kubernetes experience'", prefixIcon: const Icon(Icons.tune, size: 20)),
                  style: TextStyle(fontSize: 12.5, color: isDark ? Colors.white : Colors.black87),
                ),
                const SizedBox(height: 16),

                // Generate Button
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.shade800,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _isGeneratingManual ? null : _generateManualJobApplicationWithAI,
                    icon: _isGeneratingManual
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(
                      _isGeneratingManual ? 'Generating Application with AI...' : 'Generate Application with Gemini AI',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildExtractedJobCard(JobApplication app, int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtextColor = isDark ? Colors.white70 : Colors.black54;

    final emailCtrl = _getController(_emailControllers, index, app.recipientEmail);
    final subjectCtrl = _getController(_subjectControllers, index, app.generatedSubject);
    final bodyCtrl = _getController(_bodyControllers, index, app.generatedCoverLetter);
    final refineCtrl = _getController(_refinePromptControllers, index, '');
    final isRefining = _refiningMap[index] ?? false;

    final currentEmail = emailCtrl.text.trim().isNotEmpty ? emailCtrl.text.trim() : app.recipientEmail;
    final duplicateApp = _findExistingApplication(currentEmail, app.jobTitle, app.companyName);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: isDark ? 3 : 1,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: isDark ? Colors.blue.shade900 : Colors.blue.shade100,
                  child: Icon(Icons.work, color: isDark ? Colors.blue.shade100 : Colors.blue.shade900),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(app.jobTitle, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
                      Text(app.companyName, style: TextStyle(color: subtextColor, fontSize: 13)),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: subtextColor),
                  tooltip: 'Remove',
                  onPressed: () {
                    setState(() {
                      _extractedJobs.removeAt(index);
                      _emailControllers.remove(index)?.dispose();
                      _subjectControllers.remove(index)?.dispose();
                      _bodyControllers.remove(index)?.dispose();
                      _refinePromptControllers.remove(index)?.dispose();
                      _refiningMap.remove(index);
                    });
                  },
                ),
              ],
            ),
            if (duplicateApp != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.history_rounded, size: 16, color: Colors.amber.shade800),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Previously applied for this role on ${_formatRelativeTimestamp(duplicateApp.appliedAt)} (${duplicateApp.isAutoApplied ? "Auto-Apply" : "Manual"})',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.amber.shade300 : Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const Divider(height: 24),

            // HR Email Field
            TextFormField(
              controller: emailCtrl,
              decoration: const InputDecoration(
                labelText: 'Recipient HR Email',
                prefixIcon: Icon(Icons.email_outlined, size: 20),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.emailAddress,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor),
            ),
            const SizedBox(height: 12),

            // Email Subject Field
            TextFormField(
              controller: subjectCtrl,
              decoration: const InputDecoration(
                labelText: 'Email Subject Line',
                prefixIcon: Icon(Icons.subject, size: 20),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor),
            ),
            const SizedBox(height: 12),

            // Extracted Skills
            if (app.extractedSkills.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: app.extractedSkills
                    .map((sk) => Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(sk, style: TextStyle(fontSize: 11, color: isDark ? Colors.white : Colors.black87)),
                          backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.blue.shade50,
                        ))
                    .toList(),
              ),
              const SizedBox(height: 10),
            ],

            // Cover Letter Body Field
            Text('Cover Letter Body (Editable):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textColor)),
            const SizedBox(height: 6),
            TextFormField(
              controller: bodyCtrl,
              maxLines: 8,
              minLines: 4,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              style: TextStyle(fontSize: 12.5, height: 1.45, color: textColor),
            ),
            const SizedBox(height: 14),

            // AI Refinement Box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF332A15) : Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isDark ? Colors.amber.shade700 : Colors.amber.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_fix_high, size: 18, color: isDark ? Colors.amber.shade300 : Colors.amber.shade900),
                      const SizedBox(width: 6),
                      Text(
                        'Refine with Gemini AI',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.amber.shade300 : Colors.amber.shade900),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: refineCtrl,
                    decoration: InputDecoration(
                      hintText: "e.g., 'Make it more concise', 'Highlight my AWS certification', 'Tone down enthusiasm'",
                      hintStyle: TextStyle(fontSize: 12, color: subtextColor),
                      fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                      filled: true,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    style: TextStyle(fontSize: 12, color: textColor),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber.shade700,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: isRefining ? null : () => _refineJobWithAI(index),
                      icon: isRefining
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.bolt, size: 16),
                      label: Text(isRefining ? 'Refining...' : 'Refine Cover Letter'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _openNativeMailApp(app, index),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Open Mail App'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
                  onPressed: () => _sendApplicationEmail(app, index),
                  icon: const Icon(Icons.send, size: 16),
                  label: const Text('Send Email Now'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // ============================================================================
  // TAB 3: APPLIED HISTORY TAB
  // ============================================================================

  Widget _buildHistoryTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtextColor = isDark ? Colors.white70 : Colors.black54;

    return StreamBuilder<List<JobApplication>>(
      initialData: _service.cachedApplications,
      stream: _applicationsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final allApps = snapshot.data ?? [];
        // Applied History tab is strictly for manual applications (e.g. screenshot scans)
        final allManualApps = allApps.where((a) => !a.isAutoApplied).toList();

        // Filter by selected month
        final monthManualApps = allManualApps.where((a) =>
            a.appliedAt.year == _historyMonth.year &&
            a.appliedAt.month == _historyMonth.month
        ).toList();
        monthManualApps.sort((a, b) => b.appliedAt.compareTo(a.appliedAt));

        final monthReplyApps = monthManualApps.where((a) => a.status == 'reply_received').toList();

        List<JobApplication> displayApps = monthManualApps;
        if (_historyFilter == 'replies') {
          displayApps = monthReplyApps;
        }

        final totalPages = (displayApps.isEmpty ? 1 : (displayApps.length / 10).ceil());
        final safePage = _historyPage.clamp(1, totalPages);
        final startIndex = (safePage - 1) * 10;
        final pagedApps = displayApps.skip(startIndex).take(10).toList();

        return Column(
          children: [
            // Month Selector for History
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _buildMonthSelector(
                selectedMonth: _historyMonth,
                onMonthChanged: (m) => setState(() {
                  _historyMonth = m;
                  _historyPage = 1;
                }),
                isDark: isDark,
              ),
            ),

            // Filter Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: isDark ? const Color(0xFF0F172A) : Colors.grey.shade100,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: Text(
                        'All Manual in Month (${monthManualApps.length})',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: _historyFilter == 'all' ? FontWeight.bold : FontWeight.normal,
                          color: _historyFilter == 'all'
                              ? (isDark ? Colors.purple.shade200 : Colors.purple.shade900)
                              : (isDark ? Colors.grey.shade300 : Colors.grey.shade800),
                        ),
                      ),
                      selected: _historyFilter == 'all',
                      selectedColor: isDark ? const Color(0xFF581C87) : Colors.purple.shade100,
                      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
                      side: BorderSide(
                        color: _historyFilter == 'all'
                            ? (isDark ? Colors.purpleAccent : Colors.purple)
                            : (isDark ? const Color(0xFF334155) : Colors.grey.shade300),
                      ),
                      onSelected: (val) {
                        if (val) {
                          setState(() {
                            _historyFilter = 'all';
                            _historyPage = 1;
                          });
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(
                        '💬 Replies (${monthReplyApps.length})',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: _historyFilter == 'replies' ? FontWeight.bold : FontWeight.normal,
                          color: _historyFilter == 'replies'
                              ? (isDark ? const Color(0xFF34D399) : const Color(0xFF065F46))
                              : (isDark ? Colors.grey.shade300 : Colors.grey.shade800),
                        ),
                      ),
                      selected: _historyFilter == 'replies',
                      selectedColor: isDark ? const Color(0xFF064E3B) : const Color(0xFFD1FAE5),
                      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
                      side: BorderSide(
                        color: _historyFilter == 'replies'
                            ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                            : (isDark ? const Color(0xFF334155) : Colors.grey.shade300),
                      ),
                      onSelected: (val) {
                        if (val) {
                          setState(() {
                            _historyFilter = 'replies';
                            _historyPage = 1;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: displayApps.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.photo_library_outlined, size: 56, color: subtextColor),
                            const SizedBox(height: 12),
                            Text(
                              'No Manual Applications in ${DateFormat('MMMM yyyy').format(_historyMonth)}',
                              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: textColor),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Applications sent manually via screenshot scans during this month will appear here.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: subtextColor),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Scrollbar(
                      controller: _historyScrollController,
                      child: ListView.builder(
                        controller: _historyScrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        itemCount: pagedApps.length + (totalPages > 1 ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == pagedApps.length) {
                            return _buildPaginationBar(
                              currentPage: safePage,
                              totalPages: totalPages,
                              onPageChanged: (p) => setState(() => _historyPage = p),
                              isDark: isDark,
                            );
                          }
                          final app = pagedApps[index];
                          final bool isBounced = app.isBounced || app.status == 'bounced' || app.responseType == 'bounced';
                          final bool hasReplied = app.status == 'reply_received' || (app.responseType != null && app.responseType!.isNotEmpty && !isBounced);

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            color: cardBg,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: isBounced
                                  ? BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.4), width: 1)
                                  : BorderSide.none,
                            ),
                            child: ExpansionTile(
                              leading: CircleAvatar(
                                backgroundColor: isBounced
                                    ? const Color(0xFFEF4444).withValues(alpha: 0.18)
                                    : (hasReplied
                                        ? const Color(0xFF10B981).withValues(alpha: 0.2)
                                        : Colors.purple.withValues(alpha: 0.15)),
                                child: Icon(
                                  isBounced
                                      ? Icons.error_outline_rounded
                                      : (hasReplied
                                          ? Icons.mark_email_unread_rounded
                                          : Icons.photo_library_outlined),
                                  color: isBounced
                                      ? const Color(0xFFEF4444)
                                      : (hasReplied
                                          ? const Color(0xFF10B981)
                                          : Colors.purple),
                                  size: 18,
                                ),
                              ),
                              title: Text(app.jobTitle, style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 2),
                                  Text(
                                    '${app.companyName} • ${app.recipientEmail}',
                                    style: TextStyle(fontSize: 11.5, color: subtextColor),
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      if (isBounced)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEF4444).withValues(alpha: 0.18),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.45)),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.error_outline_rounded, size: 10, color: Color(0xFFEF4444)),
                                              SizedBox(width: 3),
                                              Text(
                                                'Address Not Found',
                                                style: TextStyle(fontSize: 9.5, color: Color(0xFFEF4444), fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                        )
                                      else if (hasReplied)
                                        _buildResponseBadge(app, isDark),
                                      if (app.resumeProfileName != null && app.resumeProfileName!.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: Colors.teal.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.picture_as_pdf_rounded, size: 10, color: Colors.teal),
                                              const SizedBox(width: 3),
                                              Text(
                                                'Resume: ${app.resumeProfileName}',
                                                style: const TextStyle(fontSize: 9.5, color: Colors.teal, fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                        ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: Colors.purple.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          '📸 Manual / Scan',
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.purple,
                                          ),
                                        ),
                                      ),
                                      if (app.modelUsed != null && app.modelUsed!.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: Colors.indigo.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.psychology_rounded, size: 10, color: Colors.indigoAccent),
                                              const SizedBox(width: 3),
                                              Text(
                                                'AI: ${app.modelUsed}',
                                                style: const TextStyle(fontSize: 9.5, color: Colors.indigoAccent, fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                        ),
                                      Text(
                                        'Applied: ${app.appliedAt.day}/${app.appliedAt.month}/${app.appliedAt.year} ${app.appliedAt.hour.toString().padLeft(2, '0')}:${app.appliedAt.minute.toString().padLeft(2, '0')}',
                                        style: TextStyle(fontSize: 10, color: subtextColor),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                onPressed: () => _service.deleteJobApplication(app.id),
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(14.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (isBounced || hasReplied)
                                        _buildRecruiterReplyCard(app, isDark),
                                      Text(
                                        'Subject: ${app.generatedSubject}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: isDark ? Colors.black26 : Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          app.generatedCoverLetter,
                                          style: TextStyle(fontSize: 11.5, height: 1.4, color: isDark ? Colors.white70 : Colors.black87),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  // ============================================================================
  // TAB 2: STARTUP RADAR (SEED / SERIES A & HIGH-GROWTH TECH STARTUPS)
  // ============================================================================

  Future<void> _triggerNetworkingDiscoveryNow() async {
    final domains = _radarTechDomains.isNotEmpty
        ? _radarTechDomains
        : _targetRolesController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    if (domains.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one Target Tech Domain / Role before running Startup Radar (e.g. .NET Developer, Software Engineer).'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    setState(() {
      _isDiscoveringLeaders = true;
    });

    try {
      final res = await _service.triggerNetworkingDiscovery(
        applicantName: _applicantNameController.text.trim().isNotEmpty ? _applicantNameController.text.trim() : null,
        targetRoles: domains,
        targetLocations: _radarLocations.isNotEmpty ? _radarLocations : null,
      );

      final count = res['count'] ?? 0;
      final msg = res['message'] ?? 'Startup Radar scan complete.';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: count > 0 ? Colors.green : Colors.indigo,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String errorMsg;
        if (e is FirebaseFunctionsException) {
          errorMsg = e.message ?? e.toString();
        } else if (e is FirebaseException) {
          errorMsg = e.message ?? e.toString();
        } else {
          errorMsg = e.toString().replaceFirst('Exception: ', '');
        }
        if (errorMsg.contains('not-found') || errorMsg.contains('NOT_FOUND')) {
          errorMsg = 'Backend Cloud Function needs deployment. Once deployed to Firebase, Startup Radar will run live.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Startup Radar error: $errorMsg'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDiscoveringLeaders = false;
        });
      }
    }
  }

  Future<void> _saveRadarPreferences() async {
    setState(() {
      _isSavingRadarSettings = true;
    });
    try {
      final name = _applicantNameController.text.trim();
      await _service.saveApplicantName(name);

      var locs = _radarLocations.expand((e) => e.split(',')).map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().toList();
      if (locs.isEmpty && _locationsController.text.trim().isNotEmpty) {
        locs = _locationsController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      }

      var domains = _radarTechDomains.expand((e) => e.split(',')).map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().toList();
      if (domains.isEmpty && _targetRolesController.text.trim().isNotEmpty) {
        domains = _targetRolesController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      }

      // Update in-memory state with cleanly normalized chips
      setState(() {
        _radarLocations = List.from(locs);
        _radarTechDomains = List.from(domains);
      });

      await _service.saveStartupRadarSettings(
        locations: locs,
        techDomains: domains,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Startup Radar locations & tech focus preferences saved!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save preferences: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingRadarSettings = false;
        });
      }
    }
  }

  void _showAddRadarLocationDialog() {
    _newRadarLocController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Target Location'),
        content: TextField(
          controller: _newRadarLocController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. Bengaluru, Chennai, Remote, Pune',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final text = _newRadarLocController.text.trim();
              if (text.isNotEmpty) {
                final parts = text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
                setState(() {
                  for (final p in parts) {
                    if (!_radarLocations.contains(p)) {
                      _radarLocations.add(p);
                    }
                  }
                });
                _saveRadarPreferences();
              }
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showAddRadarDomainDialog() {
    _newRadarDomainController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Tech Domain / Focus'),
        content: TextField(
          controller: _newRadarDomainController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. .NET Developer, Full Stack, DevOps, Python, AI/ML',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final text = _newRadarDomainController.text.trim();
              if (text.isNotEmpty) {
                final parts = text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
                setState(() {
                  for (final p in parts) {
                    if (!_radarTechDomains.contains(p)) {
                      _radarTechDomains.add(p);
                    }
                  }
                });
                _saveRadarPreferences();
              }
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _openLinkedInProfileAndCopyNote(NetworkingLead lead) async {
    // 1. Prepare and launch LinkedIn URL immediately in user gesture (opening in a new tab on web, or external app on mobile)
    String rawUrl = lead.linkedinUrl.trim();
    if (rawUrl.isEmpty) {
      rawUrl = 'https://www.linkedin.com/search/results/all/?keywords=${Uri.encodeComponent("${lead.name} ${lead.companyName}")}';
    } else if (!rawUrl.startsWith('http://') && !rawUrl.startsWith('https://')) {
      rawUrl = 'https://$rawUrl';
    }

    try {
      await UrlLauncherHelper.openInNewTabOrExternal(rawUrl);
    } catch (e) {
      debugPrint('Could not launch LinkedIn URL: $e');
    }

    // 2. Copy the customized connection note to clipboard (guaranteeing <= 190 chars, complete sentence, no chopped words)
    if (lead.connectionNote.isNotEmpty) {
      final noteToCopy = cleanAndBoundConnectionNote(lead.connectionNote);
      await Clipboard.setData(ClipboardData(text: noteToCopy));
    }

    // 3. Advance status to 'note_sent' (Card stays visible in current month list!)
    _service.updateNetworkingLeadStatus(lead.id, 'note_sent');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Copied 200-char note! Opening LinkedIn for ${lead.name}... (Marked as Note Sent / Opened)'),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF0077B5),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _markLeadHandled(NetworkingLead lead) async {
    await _service.updateNetworkingLeadStatus(lead.id, 'note_sent');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${lead.companyName} marked as handled and moved to Completed.'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showFullPitchDialog(NetworkingLead lead) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.rocket_launch_rounded, color: Colors.indigoAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Pitch to ${lead.companyName}',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Target: ${lead.name} (${lead.currentRole})',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              if (lead.email != null && lead.email!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  'Email: ${lead.email}',
                  style: TextStyle(fontSize: 12, color: Colors.blue[600]),
                ),
              ],
              if (lead.emailSent) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, color: Colors.green, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'Email Auto-Dispatched with Resume PDF Attached',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[900]
                      : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                ),
                child: SelectableText(
                  lead.fullPitch,
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy Pitch'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: lead.fullPitch));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Pitch copied to clipboard!')),
              );
            },
          ),
          if (lead.email != null && lead.email!.isNotEmpty)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0077B5), foregroundColor: Colors.white),
              icon: const Icon(Icons.email_rounded, size: 18),
              label: const Text('Open in Email Client'),
              onPressed: () async {
                Navigator.pop(ctx);
                final mailtoUri = Uri(
                  scheme: 'mailto',
                  path: lead.email,
                  queryParameters: {
                    'subject': lead.emailSubject ??
                        '${_radarTechDomains.isNotEmpty ? _radarTechDomains.first : "Software Engineering"} for ${lead.companyName} (${_applicantNameController.text.trim().isNotEmpty ? _applicantNameController.text.trim() : "Candidate"})',
                    'body': lead.fullPitch,
                  },
                );
                await launchUrl(mailtoUri, mode: LaunchMode.externalApplication);
              },
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkingTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Scrollbar(
      controller: _networkingScrollController,
      child: SingleChildScrollView(
        controller: _networkingScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Startup Radar Header Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF1E1B4B), const Color(0xFF312E81)]
                      : [const Color(0xFFEEF2FF), const Color(0xFFE0E7FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.indigoAccent.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.indigoAccent.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.rocket_launch_rounded, color: Colors.indigoAccent, size: 22),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Startup Radar (Seed / Series A) 🚀',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: isDark ? Colors.white : const Color(0xFF1E1B4B),
                              ),
                            ),
                            const Text(
                              'Daily 11:30 AM IST automated dispatch • Max 5 startups/run',
                              style: TextStyle(fontSize: 11, color: Colors.indigoAccent, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Discovers high-growth Seed & Series A tech startups in your target locations and auto-dispatches tailored pitches with your resume PDF attached directly to CTOs & Founders. Generates ≤ 200-char LinkedIn notes for 1-tap dual outreach.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isDiscoveringLeaders ? null : _triggerNetworkingDiscoveryNow,
                      icon: _isDiscoveringLeaders
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.rocket_launch_rounded, size: 18),
                      label: Text(_isDiscoveringLeaders ? 'Scanning & Pitching Startups...' : '🚀 Scan & Pitch 5 Startups Now'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Dynamic User Preferences Box (Collapsible)
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
              ),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  initiallyExpanded: false,
                  leading: const Icon(Icons.tune_rounded, color: Colors.indigoAccent),
                  title: Text(
                    'Customize Startup Locations & Tech Stack',
                    style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    _radarLocations.isEmpty && _radarTechDomains.isEmpty
                        ? 'No target locations or domains configured'
                        : '${_radarLocations.join(', ')} • ${_radarTechDomains.join(', ')}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _applicantNameController,
                            decoration: InputDecoration(
                              labelText: 'Your Full Name (used in cold outreach & pitch sign-off)',
                              hintText: 'e.g. Roshan J or Dhanush',
                              prefixIcon: const Icon(Icons.person_outline_rounded),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              isDense: true,
                            ),
                            onChanged: (_) {
                              final name = _applicantNameController.text.trim();
                              _service.saveApplicantName(name);
                            },
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Target Locations:', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold)),
                              TextButton.icon(
                                onPressed: _showAddRadarLocationDialog,
                                icon: const Icon(Icons.add, size: 14),
                                label: const Text('Add Location', style: TextStyle(fontSize: 11)),
                              ),
                            ],
                          ),
                          _radarLocations.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 4),
                                  child: Text(
                                    'No target locations set. Tap "+ Add Location" to add (e.g. Bengaluru, Remote, All)',
                                    style: TextStyle(fontSize: 11.5, color: Colors.grey, fontStyle: FontStyle.italic),
                                  ),
                                )
                              : Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: _radarLocations.map((loc) {
                                    return Chip(
                                      label: Text(loc, style: const TextStyle(fontSize: 11.5)),
                                      onDeleted: () {
                                        setState(() {
                                          _radarLocations.remove(loc);
                                        });
                                        _saveRadarPreferences();
                                      },
                                      deleteIconColor: Colors.grey,
                                      visualDensity: VisualDensity.compact,
                                    );
                                  }).toList(),
                                ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Target Tech Domains / Roles:', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold)),
                              TextButton.icon(
                                onPressed: _showAddRadarDomainDialog,
                                icon: const Icon(Icons.add, size: 14),
                                label: const Text('Add Domain', style: TextStyle(fontSize: 11)),
                              ),
                            ],
                          ),
                          _radarTechDomains.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 4),
                                  child: Text(
                                    'No target domains set. Tap "+ Add Domain" to add (e.g. .NET Developer, Full Stack, DevOps, AI/ML)',
                                    style: TextStyle(fontSize: 11.5, color: Colors.grey, fontStyle: FontStyle.italic),
                                  ),
                                )
                              : Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: _radarTechDomains.map((dom) {
                                    return Chip(
                                      label: Text(dom, style: const TextStyle(fontSize: 11.5)),
                                      onDeleted: () {
                                        setState(() {
                                          _radarTechDomains.remove(dom);
                                        });
                                        _saveRadarPreferences();
                                      },
                                      deleteIconColor: Colors.grey,
                                      visualDensity: VisualDensity.compact,
                                    );
                                  }).toList(),
                                ),
                          const SizedBox(height: 14),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton.icon(
                              onPressed: _isSavingRadarSettings ? null : _saveRadarPreferences,
                              icon: _isSavingRadarSettings
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.save_rounded, size: 14),
                              label: const Text('Save Preferences', style: TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.indigoAccent,
                                foregroundColor: Colors.white,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Month Selector for Startup Radar
            _buildMonthSelector(
              selectedMonth: _networkingMonth,
              onMonthChanged: (m) => setState(() {
                _networkingMonth = m;
                _networkingPage = 1;
              }),
              isDark: isDark,
            ),
            const SizedBox(height: 10),

            // Action Filter: Pending Outreach (Default) vs Completed vs All Startups
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildNetworkingStatusChip('pending', 'Pending Outreach ⚡'),
                  const SizedBox(width: 8),
                  _buildNetworkingStatusChip('completed', 'Completed / Sent ✅'),
                  const SizedBox(width: 8),
                  _buildNetworkingStatusChip('all', 'All Startups'),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Startup Leads Stream
            StreamBuilder<List<NetworkingLead>>(
              initialData: _service.cachedLeads,
              stream: _networkingLeadsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                final allLeads = snapshot.data ?? [];

                // 1. Filter for selected month & year
                final monthLeads = allLeads.where((l) =>
                    l.discoveredAt.year == _networkingMonth.year &&
                    l.discoveredAt.month == _networkingMonth.month
                ).toList();

                // 2. Sort latest first
                monthLeads.sort((a, b) => b.discoveredAt.compareTo(a.discoveredAt));

                // 3. Filter based on status
                var filteredLeads = monthLeads;
                if (_networkingStatusFilter == 'pending') {
                  filteredLeads = monthLeads.where((l) => l.status == 'discovered' || l.status == 'email_sent').toList();
                } else if (_networkingStatusFilter == 'completed') {
                  filteredLeads = monthLeads.where((l) => l.status == 'note_sent' || l.status == 'connected' || l.status == 'replied').toList();
                }

                if (_networkingCategoryFilter != 'all') {
                  filteredLeads = filteredLeads.where((l) => l.category == _networkingCategoryFilter).toList();
                }

                if (filteredLeads.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(32),
                    alignment: Alignment.center,
                    child: Column(
                      children: [
                        Icon(Icons.rocket_launch_rounded, size: 64, color: Colors.grey.withValues(alpha: 0.4)),
                        const SizedBox(height: 12),
                        Text(
                          _networkingStatusFilter == 'pending'
                              ? 'No Pending Outreach Leads in ${DateFormat('MMMM yyyy').format(_networkingMonth)}'
                              : 'No Startups Found in ${DateFormat('MMMM yyyy').format(_networkingMonth)}',
                          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _networkingStatusFilter == 'pending'
                              ? 'All discovered leads for this month have been addressed! Check "Completed / Sent" or "All Startups", or tap "Scan & Pitch 5 Startups Now".'
                              : 'Tap "Scan & Pitch 5 Startups Now" above or navigate to another month to see discovered startups.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  );
                }

                final totalPages = (filteredLeads.length / 10).ceil();
                final safePage = _networkingPage.clamp(1, totalPages);
                final startIndex = (safePage - 1) * 10;
                final displayedLeads = filteredLeads.skip(startIndex).take(10).toList();

                return Column(
                  children: [
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: displayedLeads.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (context, index) {
                        final lead = displayedLeads[index];
                        return _buildStartupLeadCard(lead, isDark, cardBg);
                      },
                    ),
                    _buildPaginationBar(
                      currentPage: safePage,
                      totalPages: totalPages,
                      onPageChanged: (p) => setState(() => _networkingPage = p),
                      isDark: isDark,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkingStatusChip(String key, String label) {
    final isSelected = _networkingStatusFilter == key;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _networkingStatusFilter = key;
            _networkingPage = 1;
          });
        }
      },
      selectedColor: const Color(0xFF4F46E5),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : null,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
    );
  }

  /// Sanitizes connection note: strips trailing ellipses or cutoffs,
  /// ensures complete sentences, avoids chopping words, and guarantees <= 190 characters.
  static String cleanAndBoundConnectionNote(String rawNote) {
    if (rawNote.trim().isEmpty) return '';
    String note = rawNote.trim();
    // Strip trailing ellipses, dashes, or incomplete markers
    note = note.replaceAll(RegExp(r'[\.\s…\-]+$'), '');
    while (note.startsWith('"') || note.startsWith("'")) {
      note = note.substring(1).trim();
    }
    while (note.endsWith('"') || note.endsWith("'")) {
      note = note.substring(0, note.length - 1).trim();
    }

    if (note.length <= 185) {
      if (!note.endsWith('.') && !note.endsWith('!')) {
        note = '$note.';
      }
      if (note.length <= 190) return note;
    }

    // Find last complete sentence ending before 185
    final matches = RegExp(r'[\.\!\?]\s+').allMatches(note);
    int lastSentenceEnd = -1;
    for (final m in matches) {
      final endIdx = m.start + 1;
      if (endIdx <= 185 && endIdx >= 70) {
        lastSentenceEnd = endIdx;
      }
    }

    if (lastSentenceEnd > 0) {
      return note.substring(0, lastSentenceEnd).trim();
    }

    // Backtrack to last complete word boundary before 175 chars
    final safeSlice = note.substring(0, 175);
    final lastSpace = safeSlice.lastIndexOf(' ');
    if (lastSpace > 40) {
      final cleanWordEnd = safeSlice.substring(0, lastSpace).replaceAll(RegExp(r'[,;:\-\s]+$'), '');
      return '$cleanWordEnd.';
    }
    return '${safeSlice.trim()}.';
  }

  Widget _buildStartupLeadCard(NetworkingLead lead, bool isDark, Color cardBg) {
    // Crisp, complete Connection Note (guaranteed <= 190 chars, no chopped words or ellipses)
    final displayNote = cleanAndBoundConnectionNote(lead.connectionNote);

    // Stage color
    Color stageBg = Colors.amber.withValues(alpha: 0.15);
    Color stageFg = Colors.amber.shade800;

    // Status visual config
    Color statusBg;
    Color statusFg;
    String statusDisplay;

    final bool isBounced = lead.isBounced || lead.status == 'bounced' || lead.responseType == 'bounced';
    final bool isReplied = lead.status == 'replied' || (lead.responseType != null && lead.responseType!.isNotEmpty && !isBounced);
    final bool hasNoEmail = lead.email == null || lead.email!.trim().isEmpty;

    if (isBounced) {
      statusBg = const Color(0xFFEF4444).withValues(alpha: 0.15);
      statusFg = const Color(0xFFEF4444);
      statusDisplay = 'Address Not Found';
    } else if (isReplied) {
      statusBg = Colors.purple.withValues(alpha: 0.15);
      statusFg = Colors.purpleAccent;
      statusDisplay = 'Reply Received 🎯';
    } else if (lead.status == 'email_sent' || lead.emailSent) {
      statusBg = Colors.teal.withValues(alpha: 0.15);
      statusFg = Colors.teal;
      statusDisplay = 'Email Sent ✉️';
    } else if (lead.status == 'note_sent') {
      statusBg = Colors.blue.withValues(alpha: 0.15);
      statusFg = Colors.blue;
      statusDisplay = 'Note Sent';
    } else if (lead.status == 'connected') {
      statusBg = Colors.green.withValues(alpha: 0.15);
      statusFg = Colors.green;
      statusDisplay = 'Connected';
    } else if (hasNoEmail) {
      statusBg = Colors.amber.withValues(alpha: 0.15);
      statusFg = Colors.amber.shade700;
      statusDisplay = 'Email Not Found';
    } else {
      statusBg = Colors.orange.withValues(alpha: 0.15);
      statusFg = Colors.orange.shade800;
      statusDisplay = 'Discovered';
    }

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isBounced
              ? const Color(0xFFEF4444).withValues(alpha: 0.5)
              : (isReplied
                  ? Colors.purpleAccent.withValues(alpha: 0.4)
                  : (lead.emailSent
                      ? Colors.green.withValues(alpha: 0.3)
                      : (isDark ? Colors.grey.shade800 : Colors.grey.shade200))),
          width: (isBounced || isReplied || lead.emailSent) ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Startup Icon/Avatar, Name, Funding Stage Badge, Company & Actions
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isBounced
                      ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                      : (isReplied
                          ? Colors.purple.withValues(alpha: 0.15)
                          : Colors.indigoAccent.withValues(alpha: 0.15)),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isBounced
                      ? Icons.error_outline_rounded
                      : (isReplied
                          ? Icons.mark_email_unread_rounded
                          : Icons.rocket_launch_rounded),
                  color: isBounced
                      ? const Color(0xFFEF4444)
                      : (isReplied
                          ? Colors.purpleAccent
                          : Colors.indigoAccent),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            lead.companyName,
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: stageBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            lead.fundingStage ?? 'Seed / Series A',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: stageFg,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${lead.name} • ${lead.currentRole}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.location_on_rounded, size: 12, color: Colors.grey[500]),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            lead.location,
                            style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (lead.email != null && lead.email!.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.email_outlined, size: 12, color: Colors.blue[400]),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              lead.email!,
                              style: TextStyle(fontSize: 11.5, color: Colors.blue[400]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Status Menu & Delete
              PopupMenuButton<String>(
                tooltip: 'Change Status',
                initialValue: lead.status,
                onSelected: (newStatus) async {
                  await _service.updateNetworkingLeadStatus(lead.id, newStatus);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'discovered', child: Text('Discovered')),
                  PopupMenuItem(value: 'email_sent', child: Text('Email Sent')),
                  PopupMenuItem(value: 'note_sent', child: Text('Note Sent')),
                  PopupMenuItem(value: 'connected', child: Text('Connected')),
                  PopupMenuItem(value: 'replied', child: Text('Replied')),
                  PopupMenuItem(value: 'bounced', child: Text('Address Not Found (Bounced)')),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        statusDisplay,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: statusFg,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.arrow_drop_down_rounded, size: 16, color: statusFg),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                tooltip: 'Delete Lead',
                onPressed: () async {
                  await _service.deleteNetworkingLead(lead.id);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Startup removed.'), duration: Duration(seconds: 2)),
                    );
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Tech Stack Chips (if present)
          if (lead.techStack != null && lead.techStack!.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: lead.techStack!.map((tech) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.blueGrey.shade800 : Colors.blueGrey.shade50),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    tech,
                    style: TextStyle(fontSize: 10.5, color: isDark ? Colors.white70 : Colors.blueGrey.shade900, fontWeight: FontWeight.w500),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
          ],

          // Email Dispatch / Reply / Bounce Status Banner
          if (isBounced)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, size: 15, color: Color(0xFFEF4444)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Delivery Failure: Address not found for ${lead.email ?? 'recipient'}. Connect on LinkedIn instead.',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFEF4444)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            )
          else if (isReplied)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.mark_email_unread_rounded, size: 15, color: Colors.purpleAccent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Founder Replied: ${lead.replySnippet ?? 'Check Replies Hub for full details'} 🎯',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.purpleAccent),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            )
          else if (lead.emailSent)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.mark_email_read_rounded, size: 15, color: Colors.green),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Pitch & Resume PDF dispatched to ${lead.email ?? 'Founder'} ✉️',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            )
          else if (hasNoEmail)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.25)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.person_search_rounded, size: 15, color: Colors.amber),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Email not found. Send the personalized LinkedIn connection note below.',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.amber),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

          // Connection Note Box (≤ 200 characters for LinkedIn free tier)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.notes_rounded, size: 14, color: Color(0xFF0077B5)),
                        const SizedBox(width: 4),
                        Text(
                          'LinkedIn Connection Note',
                          style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFF0077B5)),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: displayNote.length <= 200
                            ? Colors.green.withValues(alpha: 0.15)
                            : Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${displayNote.length}/200 chars',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: displayNote.length <= 200 ? Colors.green : Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SelectableText(
                  displayNote,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: isDark ? Colors.white70 : const Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // LinkedIn Outreach Status Banner (Persistent status badge)
          if (lead.status == 'note_sent' || lead.status == 'connected' || lead.status == 'replied')
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0077B5).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF0077B5).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, size: 15, color: Color(0xFF0077B5)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      lead.status == 'connected'
                          ? 'Connected in LinkedIn 🤝'
                          : (lead.status == 'replied' ? 'Founder / CTO Replied 🎯' : 'LinkedIn Note Copied & Opened 🔗'),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0077B5)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

          // Actions Row: Copy Note & Open LinkedIn, Full Pitch, Mark Handled
          Row(
            children: [
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  onPressed: () => _openLinkedInProfileAndCopyNote(lead),
                  icon: const Icon(Icons.open_in_new_rounded, size: 15),
                  label: Text(
                    lead.status == 'note_sent' || lead.status == 'connected'
                        ? 'Re-open LinkedIn & Note'
                        : 'Copy Note & Open LinkedIn',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0077B5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: () => _showFullPitchDialog(lead),
                  icon: const Icon(Icons.description_rounded, size: 15),
                  label: const Text('Full Pitch'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(fontSize: 11.5),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 20),
                tooltip: 'Mark Handled (Vanish card)',
                onPressed: () => _markLeadHandled(lead),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KeepAliveTabWrapper extends StatefulWidget {
  final Widget child;
  const _KeepAliveTabWrapper({required this.child});

  @override
  State<_KeepAliveTabWrapper> createState() => _KeepAliveTabWrapperState();
}

class _KeepAliveTabWrapperState extends State<_KeepAliveTabWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
