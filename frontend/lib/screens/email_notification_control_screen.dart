import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/log_service.dart';

class EmailNotificationControlScreen extends StatefulWidget {
  const EmailNotificationControlScreen({super.key});

  @override
  State<EmailNotificationControlScreen> createState() =>
      _EmailNotificationControlScreenState();
}

class _EmailNotificationControlScreenState
    extends State<EmailNotificationControlScreen> {
  bool _isLoading = true;
  bool _isSavingCredentials = false;
  bool _obscurePassword = true;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  Map<String, bool> _emailPrefs = {
    'job_assistant_email': true,
    'cold_outreach_email': true,
    'events_email': true,
    'walkin_email': true,
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;

        // 1. Load Email Config
        final emailConfig =
            Map<String, dynamic>.from(data['emailConfig'] ?? data['jobEmailConfig'] ?? {});
        final email = (emailConfig['email'] ?? '').toString();
        final pass = (emailConfig['appPassword'] ?? '').toString();

        _emailController.text = email.isNotEmpty ? email : (user.email ?? '');
        _passwordController.text = pass;

        // 2. Load Notification Preferences
        final prefs =
            Map<String, dynamic>.from(data['notificationPreferences'] ?? {});

        setState(() {
          _emailPrefs = {
            'job_assistant_email': prefs['job_assistant_email'] ?? true,
            'cold_outreach_email': prefs['cold_outreach_email'] ?? true,
            'events_email': prefs['events_email'] ?? true,
            'walkin_email': prefs['walkin_email'] ?? prefs['walkins_email'] ?? true,
          };
          _isLoading = false;
        });
      } else {
        _emailController.text = user.email ?? '';
        setState(() => _isLoading = false);
      }
    } catch (e) {
      LogService().error("Error loading email notification preferences", e);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveEmailCredentials() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final email = _emailController.text.trim();
    final pass = _passwordController.text.trim();

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your Gmail address.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isSavingCredentials = true);

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'emailConfig': {
          'email': email,
          'appPassword': pass,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'jobEmailConfig': {
          'email': email,
          'appPassword': pass,
        },
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Gmail credentials saved successfully!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      LogService().error("Error saving email credentials", e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save credentials: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingCredentials = false);
      }
    }
  }

  Future<void> _togglePreference(String key, bool value) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _emailPrefs[key] = value;
    });

    try {
      final Map<String, dynamic> updateData = {
        'notificationPreferences': {
          key: value,
        }
      };
      if (key == 'walkin_email') {
        (updateData['notificationPreferences'] as Map<String, dynamic>)['walkins_email'] = value;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(updateData, SetOptions(merge: true));
    } catch (e) {
      LogService().error("Error saving notification preference", e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update preference: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _openGoogleAppPasswordGuide() async {
    const urlString = 'https://myaccount.google.com/apppasswords';
    final uri = Uri.tryParse(urlString);
    if (uri != null) {
      try {
        if (kIsWeb) {
          await launchUrl(uri, webOnlyWindowName: '_blank');
        } else {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } catch (e) {
        debugPrint('Could not launch App Password URL: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF334155) : Colors.grey.shade200;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Email Notifications',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              children: [
                // 1. Info Banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: isDark ? 0.15 : 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.blue.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.mail_outline_rounded,
                          color: Colors.blueAccent, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Stay Updated in Your Inbox 📬',
                              style: GoogleFonts.outfit(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.blue.shade900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Especially useful for Web app users! RemindBuddy sends automated daily summary digests directly to your email for auto-applied jobs, startup outreach pitches, tech events, and walk-in drives.',
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.4,
                                color: isDark ? Colors.white70 : Colors.grey.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // 2. Gmail Credentials Card
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: cardBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.mark_email_read_rounded,
                                color: Colors.redAccent, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Gmail Dispatcher Credentials',
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your Gmail ID and Google App Password allow RemindBuddy to dispatch digests and job applications securely on your behalf.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Email input
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'Gmail Address',
                          hintText: 'e.g. user@gmail.com',
                          prefixIcon: const Icon(Icons.alternate_email_rounded,
                              size: 20, color: Colors.redAccent),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor:
                              isDark ? const Color(0xFF0F172A) : Colors.grey.shade50,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Password input
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: '16-Character Google App Password',
                          hintText: 'abcd efgh ijkl mnop',
                          prefixIcon: const Icon(Icons.vpn_key_rounded,
                              size: 20, color: Colors.amber),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  size: 20,
                                ),
                                onPressed: () {
                                  setState(() =>
                                      _obscurePassword = !_obscurePassword);
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.paste_rounded, size: 20),
                                tooltip: 'Paste',
                                onPressed: () async {
                                  final data = await Clipboard.getData(
                                      Clipboard.kTextPlain);
                                  if (data?.text != null) {
                                    setState(() {
                                      _passwordController.text =
                                          data!.text!.trim();
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor:
                              isDark ? const Color(0xFF0F172A) : Colors.grey.shade50,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // App password helper link
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _openGoogleAppPasswordGuide,
                          icon: const Icon(Icons.open_in_new_rounded, size: 14),
                          label: const Text(
                            'Generate App Password in Google Account ↗',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Save button
                      ElevatedButton.icon(
                        onPressed:
                            _isSavingCredentials ? null : _saveEmailCredentials,
                        icon: _isSavingCredentials
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check_rounded),
                        label: Text(
                          _isSavingCredentials
                              ? 'Saving...'
                              : 'Save Email Credentials',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 3. Email Notification Toggles
                Text(
                  'EMAIL NOTIFICATION CONTROLS ⚙️',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                    color: Colors.blueAccent,
                  ),
                ),
                const SizedBox(height: 10),

                _buildToggleCard(
                  key: 'job_assistant_email',
                  title: 'AI Auto-Apply Email Digest',
                  subtitle:
                      'Receive an automated summary email to your Gmail each time the AI agent auto-applies to new job openings.',
                  icon: Icons.rocket_launch_rounded,
                  iconColor: Colors.deepPurpleAccent,
                  isDark: isDark,
                  cardBg: cardBg,
                  cardBorder: cardBorder,
                ),
                const SizedBox(height: 12),

                _buildToggleCard(
                  key: 'cold_outreach_email',
                  title: 'Cold Outreach & Startup Pitches',
                  subtitle:
                      'Receive an automated email digest whenever new startup founders & CTOs are discovered and pitched with your resume.',
                  icon: Icons.radar_rounded,
                  iconColor: Colors.cyan,
                  isDark: isDark,
                  cardBg: cardBg,
                  cardBorder: cardBorder,
                ),
                const SizedBox(height: 12),

                _buildToggleCard(
                  key: 'events_email',
                  title: 'Tech Events & Meetups',
                  subtitle:
                      'Daily 7:00 PM IST summary email with direct registration links for new developer meetups, conferences, and hackathons.',
                  icon: Icons.event_available_rounded,
                  iconColor: Colors.teal,
                  isDark: isDark,
                  cardBg: cardBg,
                  cardBorder: cardBorder,
                ),
                const SizedBox(height: 12),

                _buildToggleCard(
                  key: 'walkin_email',
                  title: 'Walk-In Job Drives',
                  subtitle:
                      'Daily 8:00 PM IST email summary with venue locations and interview schedules for newly posted walk-in drives.',
                  icon: Icons.directions_walk_rounded,
                  iconColor: Colors.orangeAccent,
                  isDark: isDark,
                  cardBg: cardBg,
                  cardBorder: cardBorder,
                ),
              ],
            ),
    );
  }

  Widget _buildToggleCard({
    required String key,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required bool isDark,
    required Color cardBg,
    required Color cardBorder,
  }) {
    final isEnabled = _emailPrefs[key] ?? true;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder),
      ),
      child: SwitchListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        secondary: CircleAvatar(
          backgroundColor: iconColor.withValues(alpha: 0.12),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        title: Text(
          title,
          style: GoogleFonts.outfit(
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            subtitle,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: isDark ? Colors.white60 : Colors.grey.shade700,
            ),
          ),
        ),
        value: isEnabled,
        onChanged: (val) => _togglePreference(key, val),
        activeThumbColor: iconColor,
      ),
    );
  }
}
