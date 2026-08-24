import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadUserConfig();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _newAppScrollController.dispose();
    _historyScrollController.dispose();
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

    if (mounted) {
      setState(() {
        _userEmail = emailConfig['email'] ?? '';
        _userAppPassword = emailConfig['appPassword'] ?? '';
        _resumeFileName = masterResume['fileName'] ?? '';
        _hasResume = (masterResume['base64'] ?? '').isNotEmpty;
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
              if (mounted) {
                setState(() {
                  _userEmail = newEmail;
                  _userAppPassword = newPass;
                });
                Navigator.pop(ctx);
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

  Future<void> _pickJobPosters() async {
    try {
      FilePickerResult? result;
      try {
        result = await FilePicker.pickFiles(
          type: FileType.image,
          allowMultiple: true,
          withData: true,
        );
      } catch (_) {
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
          result = await FilePicker.pickFiles(
            type: FileType.any,
            allowMultiple: true,
            withData: true,
          );
        }
      }

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

          if (isImage && file.bytes != null) {
            images.add(XFile.fromData(file.bytes!, name: file.name));
            base64List.add(base64Encode(file.bytes!));
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
          SnackBar(content: Text('Error picking screenshots: $e')),
        );
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

  // ============================================================================
  // BUILD METHOD
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Job Assistant'),
        backgroundColor: Colors.blue.shade900,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amber,
          tabs: const [
            Tab(icon: Icon(Icons.add_photo_alternate), text: 'New Applications'),
            Tab(icon: Icon(Icons.history), text: 'Applied History'),
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
          _buildNewApplicationTab(),
          _buildHistoryTab(),
        ],
      ),
    );
  }

  // ============================================================================
  // TAB 1: NEW APPLICATION TAB
  // ============================================================================

  Widget _buildNewApplicationTab() {
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
              color: Colors.blue.shade50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Row(
                  children: [
                    Icon(
                      _hasResume ? Icons.picture_as_pdf : Icons.upload_file,
                      color: _hasResume ? Colors.red.shade800 : Colors.blueAccent,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _hasResume ? 'Master Resume: $_resumeFileName' : 'No Resume Uploaded Yet',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          Text(
                            _hasResume
                                ? 'This PDF will be attached & analyzed by Gemini for applications.'
                                : 'Upload your standard Resume (PDF) to auto-attach & analyze.',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _pickMasterResume,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade900,
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
            const Text('Upload Mode Strategy:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
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
                  Text(
                    'Extracted Applications (${_extractedJobs.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _extractedJobs.clear()),
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
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.purple.shade200),
      ),
      color: Colors.purple.shade50.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.language, color: Colors.purple.shade800),
                const SizedBox(width: 8),
                Text(
                  'Manual / Website URL Job Application Entry',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.purple.shade900),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'No screenshot required. Enter company details, website URL, and role to auto-generate a tailored cover letter with Gemini AI.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const Divider(height: 24),

            // Company Name & Job Title
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _manualCompanyNameController,
                    decoration: const InputDecoration(
                      labelText: 'Company Name *',
                      prefixIcon: Icon(Icons.business, size: 20),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _manualJobTitleController,
                    decoration: const InputDecoration(
                      labelText: 'Job Role / Title *',
                      prefixIcon: Icon(Icons.work_outline, size: 20),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Company URL & Recipient HR Email(s)
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _manualCompanyUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Company Website URL (Optional)',
                      hintText: 'https://company.com',
                      prefixIcon: Icon(Icons.link, size: 20),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _manualRecipientEmailsController,
                    decoration: const InputDecoration(
                      labelText: 'HR Email ID(s) (Optional)',
                      hintText: 'careers@company.com, hr@company.com',
                      prefixIcon: Icon(Icons.email_outlined, size: 20),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Company Context / Notes
            TextFormField(
              controller: _manualCompanyNotesController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Company / Job Notes & Context (Optional)',
                hintText: "e.g., 'Cloud Infrastructure consultancy looking for AWS DevOps Lead'",
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
                isDense: true,
              ),
              style: const TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 12),

            // Custom AI Instructions
            TextFormField(
              controller: _manualCustomPromptController,
              decoration: const InputDecoration(
                labelText: 'Custom AI Instructions (Optional)',
                hintText: "e.g., 'Emphasize my AWS certification & Kubernetes experience'",
                prefixIcon: Icon(Icons.tune, size: 20),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 12.5),
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
  }

  Widget _buildExtractedJobCard(JobApplication app, int index) {
    final emailCtrl = _getController(_emailControllers, index, app.recipientEmail);
    final subjectCtrl = _getController(_subjectControllers, index, app.generatedSubject);
    final bodyCtrl = _getController(_bodyControllers, index, app.generatedCoverLetter);
    final refineCtrl = _getController(_refinePromptControllers, index, '');
    final isRefining = _refiningMap[index] ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.blue.shade100,
                  child: Icon(Icons.work, color: Colors.blue.shade900),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(app.jobTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(app.companyName, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
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
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
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
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
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
                          label: Text(sk, style: const TextStyle(fontSize: 11)),
                          backgroundColor: Colors.blue.shade50,
                        ))
                    .toList(),
              ),
              const SizedBox(height: 10),
            ],

            // Cover Letter Body Field
            const Text('Cover Letter Body (Editable):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            TextFormField(
              controller: bodyCtrl,
              maxLines: 8,
              minLines: 4,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              style: const TextStyle(fontSize: 12.5, height: 1.45),
            ),
            const SizedBox(height: 14),

            // AI Refinement Box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_fix_high, size: 18, color: Colors.amber.shade900),
                      const SizedBox(width: 6),
                      Text(
                        'Refine with Gemini AI',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.amber.shade900),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: refineCtrl,
                    decoration: const InputDecoration(
                      hintText: "e.g., 'Make it more concise', 'Highlight my AWS certification', 'Tone down enthusiasm'",
                      hintStyle: TextStyle(fontSize: 12),
                      fillColor: Colors.white,
                      filled: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    style: const TextStyle(fontSize: 12),
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
    return StreamBuilder<List<JobApplication>>(
      stream: _service.getJobApplicationsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final apps = snapshot.data ?? [];
        if (apps.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history_toggle_off, size: 64, color: Colors.grey),
                SizedBox(height: 12),
                Text('No Applied Jobs History Yet.', style: TextStyle(color: Colors.grey, fontSize: 16)),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: app.status == 'sent' ? Colors.green.shade100 : Colors.amber.shade100,
                    child: Icon(
                      app.status == 'sent' ? Icons.check_circle : Icons.pending,
                      color: app.status == 'sent' ? Colors.green.shade800 : Colors.amber.shade800,
                    ),
                  ),
                  title: Text(app.jobTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${app.companyName} • ${app.recipientEmail}\nApplied: ${app.appliedAt.toString().substring(0, 10)}'),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
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
