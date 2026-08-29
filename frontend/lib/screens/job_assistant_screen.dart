import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/job_application.dart';
import '../services/job_assistant_service.dart';

class JobAssistantScreen extends StatefulWidget {
  const JobAssistantScreen({super.key});

  @override
  State<JobAssistantScreen> createState() => _JobAssistantScreenState();
}

class _JobAssistantScreenState extends State<JobAssistantScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final JobAssistantService _service = JobAssistantService();

  // State
  String _uploadMode = 'single_job'; // 'single_job' or 'multiple_jobs'
  final List<XFile> _selectedImageFiles = [];
  final List<String> _selectedImagesBase64 = [];
  bool _isAnalyzing = false;
  List<JobApplication> _extractedJobs = [];

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

  // Auto-Apply Agent State
  bool _autoApplyEnabled = true;
  final TextEditingController _targetRolesController = TextEditingController();
  final TextEditingController _locationsController = TextEditingController();
  bool _isSavingAutoSettings = false;
  bool _isRunningAutoApply = false;
  String _autoApplyStatusMessage = '';
  final ScrollController _autoAppScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUserConfig();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _autoAppScrollController.dispose();
    _newAppScrollController.dispose();
    _historyScrollController.dispose();
    _targetRolesController.dispose();
    _locationsController.dispose();
    _customScreenshotPromptController.dispose();
    _manualCompanyNameController.dispose();
    _manualJobTitleController.dispose();
    _manualCompanyUrlController.dispose();
    _manualRecipientEmailsController.dispose();
    _manualCompanyNotesController.dispose();
    _manualCustomPromptController.dispose();
    for (var c in _emailControllers.values) { c.dispose(); }
    for (var c in _subjectControllers.values) { c.dispose(); }
    for (var c in _bodyControllers.values) { c.dispose(); }
    for (var c in _refinePromptControllers.values) { c.dispose(); }
    super.dispose();
  }

  Future<void> _loadUserConfig() async {
    final emailConfig = await _service.getUserEmailConfig();
    final masterResume = await _service.getMasterResume();
    final autoSettings = await _service.getAutoApplySettings();
    final targetRoles = List<String>.from(autoSettings['targetRoles'] ?? []);
    final locations = List<String>.from(autoSettings['locations'] ?? []);

    if (mounted) {
      setState(() {
        _userEmail = emailConfig['email'] ?? '';
        _userAppPassword = emailConfig['appPassword'] ?? '';
        _resumeFileName = masterResume['fileName'] ?? '';
        _hasResume = (masterResume['base64'] ?? '').isNotEmpty;
        _autoApplyEnabled = autoSettings['enabled'] ?? true;
        _targetRolesController.text = targetRoles.isNotEmpty
            ? targetRoles.join(', ')
            : 'DevOps Engineer, Cloud Engineer, Site Reliability Engineer, Flutter Developer';
        _locationsController.text = locations.isNotEmpty
            ? locations.join(', ')
            : 'Bengaluru, India, Remote';
      });
    }
  }

  // ============================================================================
  // DIALOGS & ACTIONS
  // ============================================================================

  void _showEmailConfigDialog() {
    final emailController = TextEditingController(text: _userEmail);
    final passwordController = TextEditingController(text: _userAppPassword);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.mark_email_read, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('Gmail Sender Settings'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter your Gmail and App Password to allow RemindBuddy to send job application emails automatically in the background on your behalf.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(
                  labelText: 'Your Gmail Address',
                  prefixIcon: Icon(Icons.email_outlined),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Gmail App Password (16 chars)',
                  prefixIcon: Icon(Icons.key_outlined),
                  border: OutlineInputBorder(),
                  helperText: 'Google Account > Security > App Passwords',
                ),
              ),
            ],
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
              final newEmail = emailController.text.trim();
              final newPass = passwordController.text.trim();
              await _service.saveUserEmailConfig(newEmail, newPass);
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
              if (mounted) {
                setState(() {
                  _userEmail = newEmail;
                  _userAppPassword = newPass;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Email settings saved successfully!')),
                );
              }
            },
            child: const Text('Save Credentials', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _pickMasterResume() async {
    try {
      FilePickerResult? result;
      try {
        result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf'],
          withData: true,
        );
      } catch (_) {
        result = await FilePicker.pickFiles(
          type: FileType.any,
          withData: true,
        );
      }

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (!file.name.toLowerCase().endsWith('.pdf')) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please select a valid PDF file for your resume.')),
            );
          }
          return;
        }

        final bytes = file.bytes;
        final fileName = file.name;

        if (bytes != null) {
          final b64 = base64Encode(bytes);
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
      final picker = ImagePicker();
      final List<XFile> images = await picker.pickMultiImage();
      if (images.isNotEmpty) {
        final List<String> base64List = [];
        for (final img in images) {
          final bytes = await img.readAsBytes();
          base64List.add(base64Encode(bytes));
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
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.any,
        allowMultiple: true,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final List<XFile> images = [];
        final List<String> base64List = [];

        for (final file in result.files) {
          final nameLower = file.name.toLowerCase();
          final isImage = nameLower.endsWith('.png') ||
              nameLower.endsWith('.jpg') ||
              nameLower.endsWith('.jpeg') ||
              nameLower.endsWith('.webp') ||
              nameLower.endsWith('.bmp');

          if (isImage) {
            Uint8List? bytes = file.bytes;
            if (bytes == null && file.path != null && !kIsWeb) {
              final ioFile = File(file.path!);
              bytes = await ioFile.readAsBytes();
            }
            if (bytes != null) {
              images.add(XFile.fromData(bytes, name: file.name));
              base64List.add(base64Encode(bytes));
            }
          }
        }

        if (images.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please select valid image files (.png, .jpg, .jpeg, .webp).')),
            );
          }
          return;
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
      try {
        final picker = ImagePicker();
        final List<XFile> images = await picker.pickMultiImage();
        if (images.isNotEmpty) {
          final List<String> base64List = [];
          for (final img in images) {
            final bytes = await img.readAsBytes();
            base64List.add(base64Encode(bytes));
          }
          setState(() {
            _selectedImageFiles.addAll(images);
            _selectedImagesBase64.addAll(base64List);
          });
          return;
        }
      } catch (_) {
        await _pickFromFiles();
      }
    }
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error analyzing posters: $e')),
        );
      }
    }
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
    final roles = _targetRolesController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final locs = _locationsController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    setState(() => _isSavingAutoSettings = true);
    try {
      await _service.saveAutoApplySettings(
        enabled: _autoApplyEnabled,
        targetRoles: roles.isNotEmpty ? roles : ['DevOps Engineer', 'Cloud Engineer', 'Flutter Developer'],
        locations: locs.isNotEmpty ? locs : ['Bengaluru', 'India', 'Remote'],
        maxPerRun: 4,
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
    if (!_hasResume) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload your Master Resume PDF first in New Applications tab.')),
      );
      return;
    }
    if (_userEmail.isEmpty || _userAppPassword.isEmpty) {
      _showEmailConfigDialog();
      return;
    }

    final roles = _targetRolesController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final locs = _locationsController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    setState(() {
      _isRunningAutoApply = true;
      _autoApplyStatusMessage = 'Searching LinkedIn & job boards for verified HR postings (0-3 yrs)...';
    });

    try {
      final res = await _service.triggerAutoJobDiscoveryAndApply(
        targetRoles: roles,
        locations: locs,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Auto-apply failed: $e'), backgroundColor: Colors.redAccent),
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

  // ============================================================================
  // BUILD METHOD
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'AI Job Applicant 💼',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        elevation: 2,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amber,
          indicatorWeight: 3.0,
          tabs: const [
            Tab(icon: Icon(Icons.bolt_rounded), text: 'Auto-Apply Agent'),
            Tab(icon: Icon(Icons.add_photo_alternate_rounded), text: 'Manual & Scan'),
            Tab(icon: Icon(Icons.history_rounded), text: 'Applied History'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Email Credentials Settings',
            onPressed: _showEmailConfigDialog,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAutoApplyTab(),
          _buildNewApplicationTab(),
          _buildHistoryTab(),
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
                          _saveAutoApplySettings();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  // Health checklist: Resume & Gmail
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              _hasResume ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                              color: _hasResume ? const Color(0xFF10B981) : Colors.orange,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _hasResume ? 'Resume: $_resumeFileName' : 'Resume: Not uploaded',
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
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              (_userEmail.isNotEmpty && _userAppPassword.isNotEmpty)
                                  ? Icons.check_circle_rounded
                                  : Icons.warning_amber_rounded,
                              color: (_userEmail.isNotEmpty && _userAppPassword.isNotEmpty)
                                  ? const Color(0xFF10B981)
                                  : Colors.orange,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                (_userEmail.isNotEmpty && _userAppPassword.isNotEmpty)
                                    ? 'Gmail: $_userEmail'
                                    : 'Gmail: Not configured',
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
                    ],
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
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '🎯 Target Roles & Locations',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        if (_isSavingAutoSettings)
                          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        else
                          TextButton.icon(
                            onPressed: _saveAutoApplySettings,
                            icon: const Icon(Icons.save_outlined, size: 16),
                            label: const Text('Save Settings', style: TextStyle(fontSize: 12)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _targetRolesController,
                      decoration: InputDecoration(
                        labelText: 'Target Job Roles (comma-separated)',
                        hintText: 'e.g. DevOps Engineer, Cloud Engineer, Flutter Developer',
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
                    const SizedBox(height: 14),
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
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.filter_alt_rounded, color: Colors.teal, size: 14),
                              SizedBox(width: 4),
                              Text('Experience: 0 – 3 Years', style: TextStyle(fontSize: 11, color: Colors.teal, fontWeight: FontWeight.bold)),
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
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // On-Demand Discovery & Apply Trigger Button
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
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.rocket_launch_rounded),
                label: Text(
                  _isRunningAutoApply ? 'Agent Discovering & Applying...' : '🚀 Run Auto-Discovery & Apply Now',
                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold),
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

            // Recent Auto-Applied Applications Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '📬 Recent Automated Applications',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 10),

            StreamBuilder<List<JobApplication>>(
              stream: _service.getJobApplicationsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
                }

                final apps = snapshot.data ?? [];
                if (apps.isEmpty) {
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
                            'No Automated Applications Sent Yet',
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

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: apps.length > 10 ? 10 : apps.length,
                  itemBuilder: (context, index) {
                    final app = apps[index];
                    return _buildAutoAppCard(app, isDark);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoAppCard(JobApplication app, bool isDark) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      elevation: 1.5,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: Colors.blueAccent.withValues(alpha: 0.15),
          child: const Icon(Icons.send_rounded, color: Colors.blueAccent, size: 18),
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
            const SizedBox(height: 3),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('Sent with Resume PDF', style: TextStyle(fontSize: 9.5, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 6),
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
  }

  // ============================================================================
  // TAB 1: NEW APPLICATION TAB
  // ============================================================================

  Widget _buildNewApplicationTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.blue.shade50;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtextColor = isDark ? Colors.white70 : Colors.black54;

    return Scrollbar(
      controller: _newAppScrollController,
      child: SingleChildScrollView(
        controller: _newAppScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner: Resume Status & Upload Button
            Card(
              color: cardBg,
              elevation: isDark ? 3 : 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Row(
                  children: [
                    Icon(
                      _hasResume ? Icons.picture_as_pdf : Icons.upload_file,
                      color: _hasResume ? (isDark ? Colors.redAccent : Colors.red.shade800) : Colors.blueAccent,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _hasResume ? 'Master Resume: $_resumeFileName' : 'No Resume Uploaded Yet',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textColor),
                          ),
                          Text(
                            _hasResume
                                ? 'This PDF will be attached & analyzed by Gemini for applications.'
                                : 'Upload your standard Resume (PDF) to auto-attach & analyze.',
                            style: TextStyle(fontSize: 12, color: subtextColor),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _pickMasterResume,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(_hasResume ? 'Change' : 'Upload'),
                    ),
                  ],
                ),
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
                  label: const Text('📄 1 Job (Multi-page Screenshot)'),
                  selected: _uploadMode == 'single_job',
                  selectedColor: Colors.blue.shade100,
                  onSelected: (val) {
                    if (val) setState(() => _uploadMode = 'single_job');
                  },
                ),
                ChoiceChip(
                  label: const Text('📁 Multiple Separate Screenshots'),
                  selected: _uploadMode == 'multiple_jobs',
                  selectedColor: Colors.blue.shade100,
                  onSelected: (val) {
                    if (val) setState(() => _uploadMode = 'multiple_jobs');
                  },
                ),
                ChoiceChip(
                  label: const Text('✍️ Manual / Website URL (No Screenshot)'),
                  selected: _uploadMode == 'manual_url',
                  selectedColor: Colors.purple.shade100,
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
              // Pick Poster Screenshots Button
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      if (_selectedImageFiles.isEmpty) ...[
                        const Icon(Icons.add_a_photo_outlined, size: 48, color: Colors.grey),
                        const SizedBox(height: 8),
                        const Text('Select 1 or more Job Poster Screenshots from LinkedIn/Gallery'),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _pickJobPosters,
                          icon: const Icon(Icons.photo_library),
                          label: const Text('Select Screenshots'),
                        ),
                      ] else ...[
                        Text('${_selectedImageFiles.length} Screenshot(s) Selected',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _selectedImageFiles
                              .map((f) => Chip(
                                    avatar: const Icon(Icons.image, size: 18),
                                    label: Text(f.name.length > 15 ? '${f.name.substring(0, 12)}...' : f.name),
                                    onDeleted: () {
                                      setState(() {
                                        final idx = _selectedImageFiles.indexOf(f);
                                        _selectedImageFiles.removeAt(idx);
                                        _selectedImagesBase64.removeAt(idx);
                                      });
                                    },
                                  ))
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 12),

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

                      if (_selectedImageFiles.isNotEmpty)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _pickJobPosters,
                              icon: const Icon(Icons.add),
                              label: const Text('Add More'),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber.shade700,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: _isAnalyzing ? null : _analyzePostersWithAI,
                              icon: _isAnalyzing
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                    )
                                  : const Icon(Icons.psychology),
                              label: Text(_isAnalyzing ? 'Analyzing...' : 'Analyze with Gemini AI'),
                            ),
                          ],
                        ),
                    ],
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
  // TAB 2: HISTORY TAB
  // ============================================================================

  Widget _buildHistoryTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtextColor = isDark ? Colors.white70 : Colors.black54;

    return StreamBuilder<List<JobApplication>>(
      stream: _service.getJobApplicationsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final apps = snapshot.data ?? [];
        if (apps.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history_toggle_off, size: 64, color: subtextColor),
                const SizedBox(height: 12),
                Text('No Applied Jobs History Yet.', style: TextStyle(color: subtextColor, fontSize: 16)),
              ],
            ),
          );
        }

        return Scrollbar(
          controller: _historyScrollController,
          child: ListView.builder(
            controller: _historyScrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: apps.length,
            itemBuilder: (context, index) {
              final app = apps[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                color: cardBg,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: app.status == 'sent'
                        ? (isDark ? Colors.green.shade900 : Colors.green.shade100)
                        : (isDark ? Colors.amber.shade900 : Colors.amber.shade100),
                    child: Icon(
                      app.status == 'sent' ? Icons.check_circle : Icons.pending,
                      color: app.status == 'sent'
                          ? (isDark ? Colors.green.shade300 : Colors.green.shade800)
                          : (isDark ? Colors.amber.shade300 : Colors.amber.shade800),
                    ),
                  ),
                  title: Text(app.jobTitle, style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                  subtitle: Text(
                    '${app.companyName} • ${app.recipientEmail}\nApplied: ${app.appliedAt.toString().substring(0, 10)}',
                    style: TextStyle(color: subtextColor),
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    onPressed: () => _service.deleteJobApplication(app.id),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
