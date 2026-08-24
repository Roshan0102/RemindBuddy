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
      final jobs = await _service.parseJobPostersWithAI(_selectedImagesBase64, _uploadMode);
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

  Future<void> _sendApplicationEmail(JobApplication app, int index) async {
    if (_userEmail.isEmpty || _userAppPassword.isEmpty) {
      _showEmailConfigDialog();
      return;
    }

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sending application email in background...')),
      );

      await _service.sendJobApplicationEmail(app);

      setState(() {
        _extractedJobs.removeAt(index);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Job application email sent to ${app.recipientEmail}!')),
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

  Future<void> _openNativeMailApp(JobApplication app) async {
    final uri = Uri(
      scheme: 'mailto',
      path: app.recipientEmail,
      queryParameters: {
        'subject': app.generatedSubject,
        'body': app.generatedCoverLetter,
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
    return SingleChildScrollView(
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
                              ? 'This PDF will be attached to outgoing emails.'
                              : 'Upload your standard Resume (PDF) to auto-attach.',
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

          // Upload Mode Choice (Solution 2 Approved)
          const Text('Upload Mode Strategy:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Text('📄 1 Job (Multi-page)'),
                  selected: _uploadMode == 'single_job',
                  selectedColor: Colors.blue.shade100,
                  onSelected: (val) {
                    if (val) setState(() => _uploadMode = 'single_job');
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  label: const Text('📁 Multiple Separate Jobs'),
                  selected: _uploadMode == 'multiple_jobs',
                  selectedColor: Colors.blue.shade100,
                  onSelected: (val) {
                    if (val) setState(() => _uploadMode = 'multiple_jobs');
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

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
                    const SizedBox(height: 14),
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
                ],
              ),
            ),
          ),
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
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _extractedJobs.length,
              itemBuilder: (context, index) {
                return _buildExtractedJobCard(_extractedJobs[index], index);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExtractedJobCard(JobApplication app, int index) {
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
              ],
            ),
            const Divider(height: 24),

            // HR Email
            Row(
              children: [
                const Icon(Icons.email, size: 18, color: Colors.grey),
                const SizedBox(width: 6),
                const Text('Recipient HR Email: ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Expanded(
                  child: Text(
                    app.recipientEmail.isEmpty ? 'Not Found' : app.recipientEmail,
                    style: TextStyle(
                      color: app.recipientEmail.isEmpty ? Colors.red : Colors.blue.shade900,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

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

            // Cover Letter Preview
            const Text('Generated Cover Letter:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                app.generatedCoverLetter,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
            ),
            const SizedBox(height: 14),

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _openNativeMailApp(app),
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

        return ListView.builder(
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
        );
      },
    );
  }
}
