import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:share_plus/share_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/update_service.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _geminiApiKeyController = TextEditingController();
  bool _obscurePrimaryGemini = true;
  final _adminUserUsernameController = TextEditingController();
  final _adminUserPasswordController = TextEditingController();
  final _latestStableVersionController = TextEditingController();
  final _latestStaticVersionController = TextEditingController();

  List<Map<String, String>> _allUsers = [];
  List<String> _selectedBetaTesterUids = [];
  List<String> _selectedStaticUserUids = [];
  String _latestGitHubBetaVersion = '';
  bool _isFetchingGithub = false;

  bool _isAuthenticated = false;
  bool _isLoading = true;
  String _errorMessage = '';
  String _geminiApiKeySuccessMessage = '';
  bool _isAdminUserActionLoading = false;
  String _adminUserSuccessMessage = '';
  String _adminUserErrorMessage = '';

  final List<Map<String, dynamic>> _availableModules = [
    {
      'id': 'gold',
      'label': 'Gold Rates',
      'icon': Icons.monetization_on_rounded,
      'color': const Color(0xFFF59E0B),
    },
    {
      'id': 'gold_chit',
      'label': 'Gold Chit Tracker',
      'icon': Icons.savings_rounded,
      'color': const Color(0xFFEAB308),
    },
    {
      'id': 'reminders',
      'label': 'Calendar Reminders',
      'icon': Icons.calendar_month_rounded,
      'color': const Color(0xFF3B82F6),
    },
    {
      'id': 'daily_reminders',
      'label': 'Daily Reminders',
      'icon': Icons.alarm_rounded,
      'color': const Color(0xFF06B6D4),
    },
    {
      'id': 'notes',
      'label': 'Aesthetic Notes',
      'icon': Icons.edit_note_rounded,
      'color': const Color(0xFF8B5CF6),
    },
    {
      'id': 'shifts',
      'label': 'My Shifts',
      'icon': Icons.schedule_rounded,
      'color': const Color(0xFF10B981),
    },
    {
      'id': 'job_assistant',
      'label': 'AI Job Assistant',
      'icon': Icons.work_rounded,
      'color': const Color(0xFF6366F1),
    },
    {
      'id': 'finance',
      'label': 'Finance & Split Expenses',
      'icon': Icons.account_balance_wallet_rounded,
      'color': const Color(0xFF14B8A6),
    },
    {
      'id': 'vault',
      'label': 'Secure Vault',
      'icon': Icons.lock_rounded,
      'color': const Color(0xFFEC4899),
    },
    {
      'id': 'events',
      'label': 'Tech Events',
      'icon': Icons.event_available_rounded,
      'color': const Color(0xFFF97316),
    },
    {
      'id': 'walkin',
      'label': 'Walk-In Drives',
      'icon': Icons.directions_walk_rounded,
      'color': const Color(0xFF38BDF8),
    },
    {
      'id': 'voice_assistant',
      'label': 'Voice Assistant',
      'icon': Icons.mic_rounded,
      'color': const Color(0xFFA855F7),
    },
    {
      'id': 'ask_gemini',
      'label': 'Ask Gemini Buttons',
      'icon': Icons.auto_awesome_rounded,
      'color': const Color(0xFF0284C7),
    },
    {
      'id': 'gcp_cost',
      'label': 'GCP Cost Tracker',
      'icon': Icons.cloud_outlined,
      'color': const Color(0xFF64748B),
    },
    {
      'id': 'astro_calendar',
      'label': 'Astro Calendar',
      'icon': Icons.nightlight_round,
      'color': const Color(0xFFD946EF),
    },
    {
      'id': 'sms_study',
      'label': 'SMS Study Sync (15 Days)',
      'icon': Icons.sms_rounded,
      'color': const Color(0xFF059669),
    },
  ];

  @override
  void initState() {
    super.initState();
    _checkLocalAuth();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _geminiApiKeyController.dispose();
    _adminUserUsernameController.dispose();
    _adminUserPasswordController.dispose();
    _latestStableVersionController.dispose();
    _latestStaticVersionController.dispose();
    super.dispose();
  }

  Future<void> _checkLocalAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final isAuth = prefs.getBool('isAdminAuthenticated') ?? false;
    setState(() {
      _isAuthenticated = isAuth;
      _isLoading = false;
    });
    if (isAuth) {
      _fetchGeminiApiKey();
      _fetchAppUpdatesConfig();
    }
  }

  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please enter username and password.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final doc = await FirebaseFirestore.instance
          .collection('admin_creds')
          .doc('login')
          .get();

      if (doc.exists && doc.data() != null) {
        final dbUsername = doc.data()!['username'];
        final dbPassword = doc.data()!['password'];

        if (username == dbUsername && password == dbPassword) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('isAdminAuthenticated', true);
          await _fetchGeminiApiKey();
          await _fetchAppUpdatesConfig();
          setState(() {
            _isAuthenticated = true;
            _errorMessage = '';
            _isLoading = false;
          });
          return;
        }
      }

      setState(() {
        _errorMessage = 'Invalid username or password.';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error authenticating: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isAdminAuthenticated', false);
    setState(() {
      _isAuthenticated = false;
      _usernameController.clear();
      _passwordController.clear();
      _geminiApiKeyController.clear();
    });
  }

  Future<void> _fetchGeminiApiKey() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('admin_creds')
          .doc('gemini_config')
          .get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        _geminiApiKeyController.text = data['apiKey'] ?? '';
      }
    } catch (e) {
      debugPrint('Error fetching Gemini API key: $e');
    }
  }

  Future<void> _fetchAppUpdatesConfig() async {
    setState(() {
      _isLoading = true;
      _isFetchingGithub = true;
    });

    try {
      // 1. Fetch all users from usernames collection
      final usernamesSnap =
          await FirebaseFirestore.instance.collection('usernames').get();
      final List<Map<String, String>> usersList = [];
      for (var doc in usernamesSnap.docs) {
        final data = doc.data();
        final username = doc.id;
        final uid = data['uid'] as String? ?? '';
        if (uid.isNotEmpty) {
          usersList.add({'username': username, 'uid': uid});
        }
      }

      // 2. Fetch latest tag from GitHub (the automatic beta version)
      final latestGitTag = await UpdateService.fetchLatestGitHubTag();

      // 3. Fetch app_updates config from Firestore
      final doc = await FirebaseFirestore.instance
          .collection('admin_creds')
          .doc('app_updates')
          .get();

      String stableVersion = '';
      String staticVersion = '';
      List<dynamic> uids = [];
      List<dynamic> staticUids = [];

      if (doc.exists && doc.data() != null) {
        stableVersion = doc.data()!['latest_stable_version'] ?? '';
        staticVersion = doc.data()!['latest_static_version'] ?? '';
        uids = doc.data()!['beta_tester_uids'] ?? [];
        staticUids = doc.data()!['static_user_uids'] ?? [];
      }

      setState(() {
        _allUsers = usersList;
        _selectedBetaTesterUids = List<String>.from(uids);
        _selectedStaticUserUids = List<String>.from(staticUids);
        _latestGitHubBetaVersion = latestGitTag;
        _latestStableVersionController.text = stableVersion;
        _latestStaticVersionController.text = staticVersion;
        _isLoading = false;
        _isFetchingGithub = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isFetchingGithub = false;
      });
      debugPrint('Error fetching App Updates config: $e');
    }
  }

  Future<void> _updateGeminiApiKey() async {
    final primaryKey = _geminiApiKeyController.text.trim();

    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance
          .collection('admin_creds')
          .doc('gemini_config')
          .set({
        'apiKey': primaryKey,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      setState(() {
        _geminiApiKeySuccessMessage =
            'Admin Gemini API Key updated successfully!';
        _isLoading = false;
      });

      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _geminiApiKeySuccessMessage = '';
          });
        }
      });
    } catch (e) {
      setState(() {
        _geminiApiKeySuccessMessage = 'Error updating key: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _updateAppUpdatesConfig() async {
    setState(() => _isLoading = true);

    // Map selected UIDs back to usernames for storage
    final List<String> betaUsernames = [];
    for (var uid in _selectedBetaTesterUids) {
      final userMap =
          _allUsers.firstWhere((u) => u['uid'] == uid, orElse: () => {});
      if (userMap.isNotEmpty && userMap['username'] != null) {
        betaUsernames.add(userMap['username']!);
      }
    }

    final List<String> staticUsernames = [];
    for (var uid in _selectedStaticUserUids) {
      final userMap =
          _allUsers.firstWhere((u) => u['uid'] == uid, orElse: () => {});
      if (userMap.isNotEmpty && userMap['username'] != null) {
        staticUsernames.add(userMap['username']!);
      }
    }

    try {
      await FirebaseFirestore.instance
          .collection('admin_creds')
          .doc('app_updates')
          .set({
        'latest_stable_version': _latestStableVersionController.text.trim(),
        'latest_static_version': _latestStaticVersionController.text.trim(),
        'latest_beta_version': _latestGitHubBetaVersion.isNotEmpty
            ? _latestGitHubBetaVersion
            : '1.6.9', // fallback
        'beta_tester_uids': _selectedBetaTesterUids,
        'beta_tester_usernames': betaUsernames,
        'static_user_uids': _selectedStaticUserUids,
        'static_user_usernames': staticUsernames,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  'App Updates configuration saved!',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to update config: $e',
              style: GoogleFonts.outfit(),
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _toggleModule(
    String userId,
    String moduleId,
    bool enable,
    List<String> enabledModules,
  ) async {
    final newModules = List<String>.from(enabledModules);
    if (enable) {
      if (!newModules.contains(moduleId)) newModules.add(moduleId);
    } else {
      newModules.remove(moduleId);
    }

    try {
      await FirebaseFunctions.instance
          .httpsCallable('adminUpdateUserModules')
          .call({
            'userId': userId,
            'enabledModules': newModules,
          });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error updating user permissions: ${e.toString().replaceAll("Exception:", "")}',
              style: GoogleFonts.outfit(),
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _adminCreateUser() async {
    final username = _adminUserUsernameController.text.trim();
    final password = _adminUserPasswordController.text.trim();
    if (username.isEmpty || password.isEmpty) {
      setState(
        () => _adminUserErrorMessage = 'Username and password are required.',
      );
      return;
    }
    if (password.length < 6) {
      setState(
        () => _adminUserErrorMessage = 'Password must be at least 6 characters.',
      );
      return;
    }

    // Fetch existing usernames for the collaboration partner pop-up
    final usernamesSnap =
        await FirebaseFirestore.instance.collection('usernames').get();
    final existingUsernames = usernamesSnap.docs
        .map((d) => d.id)
        .where((u) => u.toLowerCase() != username.toLowerCase())
        .toList();

    List<String> selectedPartners = [];

    if (existingUsernames.isNotEmpty) {
      if (!mounted) return;
      final result = await showDialog<List<String>>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          final List<String> tempSelected = <String>[];
          return StatefulBuilder(
            builder: (context, setPopState) {
              final isDark = Theme.of(context).brightness == Brightness.dark;
              final dialogBg = isDark ? const Color(0xFF1E293B) : Colors.white;
              final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
              final subtextColor = isDark
                  ? Colors.white60
                  : const Color(0xFF64748B);

              return AlertDialog(
                backgroundColor: dialogBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.people_alt_rounded,
                        color: Color(0xFF8B5CF6),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Allowed Partners for @$username',
                        style: GoogleFonts.outfit(
                          fontSize: 16.5,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                    ),
                  ],
                ),
                content: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select which existing users this new user is authorized to collaborate with:',
                        style: GoogleFonts.outfit(
                          fontSize: 12.5,
                          color: subtextColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            onPressed: () {
                              setPopState(() {
                                tempSelected.clear();
                                tempSelected.addAll(existingUsernames);
                              });
                            },
                            icon: const Icon(Icons.done_all_rounded, size: 16),
                            label: Text(
                              'Select All',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              setPopState(() {
                                tempSelected.clear();
                              });
                            },
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            label: Text(
                              'Deselect All',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.redAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Divider(
                        height: 16,
                        color: isDark
                            ? Colors.white12
                            : Colors.black.withValues(alpha: 0.08),
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: existingUsernames.map((u) {
                              final isChecked = tempSelected.contains(u);
                              return FilterChip(
                                label: Text(
                                  '@$u',
                                  style: GoogleFonts.outfit(
                                    color: isChecked
                                        ? Colors.white
                                        : (isDark
                                              ? Colors.white70
                                              : const Color(0xFF334155)),
                                    fontWeight: isChecked
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    fontSize: 12.5,
                                  ),
                                ),
                                selected: isChecked,
                                selectedColor: const Color(0xFF7C3AED),
                                backgroundColor: isDark
                                    ? const Color(0xFF0F172A)
                                    : const Color(0xFFF1F5F9),
                                checkmarkColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                side: BorderSide(
                                  color: isChecked
                                      ? const Color(0xFF8B5CF6)
                                      : (isDark
                                            ? Colors.white.withValues(
                                                alpha: 0.1,
                                              )
                                            : Colors.black.withValues(
                                                alpha: 0.08,
                                              )),
                                ),
                                onSelected: (val) {
                                  setPopState(() {
                                    if (val) {
                                      if (!tempSelected.contains(u)) {
                                        tempSelected.add(u);
                                      }
                                    } else {
                                      tempSelected.remove(u);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, null),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.outfit(color: subtextColor),
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context, tempSelected),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text(
                      'Create User',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              );
            },
          );
        },
      );

      if (result == null) return; // User cancelled
      selectedPartners = result;
    }

    setState(() {
      _isAdminUserActionLoading = true;
      _adminUserErrorMessage = '';
      _adminUserSuccessMessage = '';
    });
    try {
      final response = await FirebaseFunctions.instance
          .httpsCallable('adminCreateUser')
          .call({
            'username': username,
            'password': password,
            'allowedCollaborators': selectedPartners,
          });

      final resData = response.data as Map<String, dynamic>?;
      final uid = resData?['uid'] ?? '';
      if (uid.toString().isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid.toString())
            .set({
              'allowedCollaborators': selectedPartners,
            }, SetOptions(merge: true));
      }

      _adminUserUsernameController.clear();
      _adminUserPasswordController.clear();
      setState(() {
        _adminUserSuccessMessage =
            'User "$username" created with ${selectedPartners.length} allowed partner(s)!';
        _isAdminUserActionLoading = false;
      });
    } catch (e) {
      setState(() {
        _adminUserErrorMessage =
            'Failed to create user: ${e.toString().replaceAll("Exception:", "")}';
        _isAdminUserActionLoading = false;
      });
    }
  }

  Future<void> _adminChangePassword() async {
    final username = _adminUserUsernameController.text.trim();
    final password = _adminUserPasswordController.text.trim();
    if (username.isEmpty || password.isEmpty) {
      setState(
        () => _adminUserErrorMessage =
            'Username and new password are required.',
      );
      return;
    }
    setState(() {
      _isAdminUserActionLoading = true;
      _adminUserErrorMessage = '';
      _adminUserSuccessMessage = '';
    });
    try {
      await FirebaseFunctions.instance
          .httpsCallable('adminChangePassword')
          .call({'username': username, 'password': password});

      _adminUserUsernameController.clear();
      _adminUserPasswordController.clear();
      setState(() {
        _adminUserSuccessMessage =
            'Password updated successfully for user "$username"!';
        _isAdminUserActionLoading = false;
      });
    } catch (e) {
      setState(() {
        _adminUserErrorMessage =
            'Failed to change password: ${e.toString().replaceAll("Exception:", "")}';
        _isAdminUserActionLoading = false;
      });
    }
  }

  Future<void> _adminDeleteUser() async {
    final username = _adminUserUsernameController.text.trim();
    if (username.isEmpty) {
      setState(
        () => _adminUserErrorMessage =
            'Username is required to delete a user.',
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.redAccent,
                  size: 24,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Confirm Deletion',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to permanently delete user "$username" and all their associated data? This action cannot be undone.',
            style: GoogleFonts.outfit(fontSize: 13.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Cancel',
                style: GoogleFonts.outfit(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Delete User',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() {
      _isAdminUserActionLoading = true;
      _adminUserErrorMessage = '';
      _adminUserSuccessMessage = '';
    });
    try {
      await FirebaseFunctions.instance
          .httpsCallable('adminDeleteUser')
          .call({'username': username});

      _adminUserUsernameController.clear();
      _adminUserPasswordController.clear();
      setState(() {
        _adminUserSuccessMessage = 'User "$username" deleted successfully!';
        _isAdminUserActionLoading = false;
      });
    } catch (e) {
      setState(() {
        _adminUserErrorMessage =
            'Failed to delete user: ${e.toString().replaceAll("Exception:", "")}';
        _isAdminUserActionLoading = false;
      });
    }
  }

  Future<void> _toggleAllowedCollaborator(
    String userId,
    String targetUsername,
    bool allow,
    List<String> currentAllowed,
  ) async {
    final updatedList = List<String>.from(currentAllowed);
    if (allow) {
      if (!updatedList.contains(targetUsername)) {
        updatedList.add(targetUsername);
      }
    } else {
      updatedList.remove(targetUsername);
    }

    try {
      try {
        final callable = FirebaseFunctions.instance.httpsCallable(
          'adminUpdateAllowedCollaborators',
        );
        await callable.call({
          'userId': userId,
          'allowedCollaborators': updatedList,
        });
      } catch (_) {
        await FirebaseFirestore.instance.collection('users').doc(userId).set({
          'allowedCollaborators': updatedList,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error updating allowed collaborators: $e',
              style: GoogleFonts.outfit(),
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  bool _isSharingApk = false;

  Future<void> _shareLatestApk() async {
    if (_isSharingApk) return;
    setState(() => _isSharingApk = true);
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final version = packageInfo.version;

      if (!kIsWeb && Platform.isAndroid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Preparing APK file for sharing...',
                    style: GoogleFonts.outfit(),
                  ),
                ],
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }

        const platform = MethodChannel('com.remindbuddy/app_utils');
        final String? apkPath = await platform.invokeMethod<String>(
          'getAppApkPath',
        );
        if (apkPath != null &&
            File(apkPath).existsSync() &&
            (await File(apkPath).length()) > 1000000) {
          await Share.shareXFiles(
            [
              XFile(
                apkPath,
                mimeType: 'application/vnd.android.package-archive',
              ),
            ],
            text: '📥 RemindBuddy App APK (v$version)',
            subject: 'RemindBuddy App APK (v$version)',
          );
          return;
        }
      }

      // Fallback if web or non-android
      const firebaseApkUrl =
          'https://firebasestorage.googleapis.com/v0/b/remindbuddy-b68f9.firebasestorage.app/o/releases%2Flatest-release.apk?alt=media';
      final shareText =
          '''
📱 *RemindBuddy App (v${packageInfo.version})*
Download latest release APK:
$firebaseApkUrl
'''
              .trim();

      await Share.share(shareText, subject: 'Download RemindBuddy App APK');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error preparing APK for sharing: $e',
              style: GoogleFonts.outfit(),
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSharingApk = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? const Color(0xFF0B0F19)
        : const Color(0xFFF8FAFC);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Color(0xFF4F46E5)),
              const SizedBox(height: 16),
              Text(
                'Loading Admin Controls...',
                style: GoogleFonts.outfit(
                  color: isDark ? Colors.white70 : const Color(0xFF64748B),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isAuthenticated) {
      return _buildLoginScreen();
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: isDark
              ? const Color(0xFF0F172A)
              : Colors.white,
          elevation: 0,
          scrolledUnderElevation: 1,
          centerTitle: false,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4F46E5).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.admin_panel_settings_rounded,
                  size: 19,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Admin Control Panel',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: textColor,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0xFF6366F1).withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.share_rounded,
                  size: 18,
                  color: isDark ? Colors.cyanAccent : const Color(0xFF4F46E5),
                ),
              ),
              onPressed: _shareLatestApk,
              tooltip: 'Share App APK',
            ),
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  size: 18,
                  color: Colors.redAccent,
                ),
              ),
              onPressed: _handleLogout,
              tooltip: 'Logout Admin',
            ),
            const SizedBox(width: 8),
          ],
          bottom: TabBar(
            indicatorColor: const Color(0xFF4F46E5),
            indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: const Color(0xFF4F46E5),
            unselectedLabelColor: isDark
                ? Colors.white60
                : const Color(0xFF64748B),
            labelStyle: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              fontSize: 13.5,
            ),
            unselectedLabelStyle: GoogleFonts.outfit(
              fontWeight: FontWeight.w500,
              fontSize: 13.5,
            ),
            tabs: const [
              Tab(
                icon: Icon(Icons.tune_rounded, size: 20),
                text: 'System Config',
              ),
              Tab(
                icon: Icon(Icons.manage_accounts_rounded, size: 20),
                text: 'User Accounts',
              ),
              Tab(
                icon: Icon(Icons.security_rounded, size: 20),
                text: 'Permissions',
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildConfigTab(),
            _buildAccountsTab(),
            _buildPermissionsTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginScreen() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? const Color(0xFF0B0F19)
        : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF161E2E) : Colors.white;
    final cardBorder = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtextColor = isDark
        ? Colors.white60
        : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'RemindBuddy Console',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Container(
              padding: const EdgeInsets.all(28.0),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: cardBorder),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.5)
                        : const Color(0xFF4F46E5).withValues(alpha: 0.06),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Glowing Icon Badge
                  Center(
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF6366F1,
                            ).withValues(alpha: 0.4),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.admin_panel_settings_rounded,
                        size: 38,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Administrator Access',
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Enter your administrative credentials to manage rollouts, modules, and user accounts.',
                    style: GoogleFonts.outfit(
                      color: subtextColor,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),

                  // Username Field
                  TextField(
                    controller: _usernameController,
                    style: GoogleFonts.outfit(color: textColor),
                    decoration: InputDecoration(
                      labelText: 'Admin Username',
                      labelStyle: GoogleFonts.outfit(color: subtextColor),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF0F172A)
                          : const Color(0xFFF1F5F9),
                      prefixIcon: const Icon(
                        Icons.person_rounded,
                        color: Color(0xFF6366F1),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: cardBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: Color(0xFF4F46E5),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Password Field
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    style: GoogleFonts.outfit(color: textColor),
                    decoration: InputDecoration(
                      labelText: 'Admin Password',
                      labelStyle: GoogleFonts.outfit(color: subtextColor),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF0F172A)
                          : const Color(0xFFF1F5F9),
                      prefixIcon: const Icon(
                        Icons.lock_rounded,
                        color: Color(0xFF6366F1),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: cardBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: Color(0xFF4F46E5),
                          width: 2,
                        ),
                      ),
                    ),
                  ),

                  // Error Message
                  if (_errorMessage.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.redAccent.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: Colors.redAccent,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage,
                              style: GoogleFonts.outfit(
                                color: Colors.redAccent,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 26),

                  // Login Button
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shadowColor: const Color(
                        0xFF4F46E5,
                      ).withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _isLoading ? null : _handleLogin,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Sign In to Admin Panel',
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConfigTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF161E2E) : Colors.white;
    final cardBorder = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtextColor = isDark
        ? Colors.white60
        : const Color(0xFF64748B);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ================================================================
              // SECTION 1: GEMINI API CONFIGURATION
              // ================================================================
              Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: cardBorder),
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.3)
                          : Colors.black.withValues(alpha: 0.03),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Card Title Row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF06B6D4), Color(0xFF0284C7)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.auto_awesome_rounded,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Central Gemini API Key',
                                style: GoogleFonts.outfit(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                              Text(
                                'Backend Cloud Functions AI Engine',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  color: subtextColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF06B6D4,
                            ).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'AI CORE',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF06B6D4),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Used centrally by Cloud Functions for Gold Market Forecast & Voice Assistant AI. Model fallback cascade: Gemini 3.7 Flash ➔ Gemini 3.6 Flash ➔ Gemini 3.5 Flash.',
                      style: GoogleFonts.outfit(
                        color: subtextColor,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Gemini API Key Input
                    TextField(
                      controller: _geminiApiKeyController,
                      obscureText: _obscurePrimaryGemini,
                      style: GoogleFonts.robotoMono(
                        color: textColor,
                        fontSize: 13.5,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Admin Gemini API Key',
                        labelStyle: GoogleFonts.outfit(color: subtextColor),
                        hintText: 'AIzaSy...',
                        hintStyle: GoogleFonts.outfit(
                          color: subtextColor.withValues(alpha: 0.5),
                        ),
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF0F172A)
                            : const Color(0xFFF1F5F9),
                        prefixIcon: const Icon(
                          Icons.vpn_key_rounded,
                          color: Color(0xFF0284C7),
                          size: 20,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePrimaryGemini
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color: subtextColor,
                          ),
                          onPressed: () {
                            setState(
                              () => _obscurePrimaryGemini =
                                  !_obscurePrimaryGemini,
                            );
                          },
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: cardBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFF0284C7),
                            width: 1.8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Architecture Cascade Info Box
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(
                          0xFF3B82F6,
                        ).withValues(alpha: isDark ? 0.1 : 0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(
                            0xFF3B82F6,
                          ).withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.layers_rounded,
                            color: Color(0xFF3B82F6),
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Active Model: Gemini 3.7 Flash with automatic fallback to Gemini 3.6 Flash & 3.5 Flash. Heavy search modules (Jobs, Tech Events, Walk-Ins) use each user\'s personal BYOK keys.',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: isDark
                                    ? const Color(0xFF93C5FD)
                                    : const Color(0xFF1E40AF),
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    ElevatedButton.icon(
                      onPressed: _updateGeminiApiKey,
                      icon: const Icon(Icons.save_rounded, size: 18),
                      label: Text(
                        'Save Gemini API Key',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: const Color(0xFF0284C7),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    if (_geminiApiKeySuccessMessage.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF10B981,
                          ).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.check_circle_rounded,
                              size: 16,
                              color: Color(0xFF10B981),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _geminiApiKeySuccessMessage,
                              style: GoogleFonts.outfit(
                                color: const Color(0xFF10B981),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ================================================================
              // SECTION 2: APP UPDATES & RELEASE MANAGEMENT
              // ================================================================
              Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: cardBorder),
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.3)
                          : Colors.black.withValues(alpha: 0.03),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Card Title Row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.rocket_launch_rounded,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'App Updates & Rollouts',
                                style: GoogleFonts.outfit(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                              Text(
                                'Release channels & tester segregation',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  color: subtextColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF8B5CF6,
                            ).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'DEPLOY',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF8B5CF6),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Control which versions of the app are promoted to stable (all users) versus beta (testers only).',
                      style: GoogleFonts.outfit(
                        color: subtextColor,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Beta version info (auto-fetched from GitHub)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF0F172A)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cardBorder),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFF59E0B,
                              ).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.bug_report_rounded,
                              color: Color(0xFFF59E0B),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Latest Beta Version (GitHub Tag)',
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    color: subtextColor,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                _isFetchingGithub
                                    ? const SizedBox(
                                        height: 16,
                                        width: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFF4F46E5),
                                        ),
                                      )
                                    : Row(
                                        children: [
                                          Text(
                                            _latestGitHubBetaVersion.isNotEmpty
                                                ? _latestGitHubBetaVersion
                                                : 'Not found',
                                            style: GoogleFonts.outfit(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: textColor,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(
                                                0xFF10B981,
                                              ).withValues(alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'Live Tag',
                                              style: GoogleFonts.outfit(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.bold,
                                                color: const Color(0xFF10B981),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                              ],
                            ),
                          ),
                          if (_latestGitHubBetaVersion.isNotEmpty)
                            ElevatedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _latestStableVersionController.text =
                                      _latestGitHubBetaVersion;
                                });
                              },
                              icon: const Icon(Icons.copy_rounded, size: 15),
                              label: Text(
                                'Promote to Stable',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(
                                  0xFF4F46E5,
                                ).withValues(alpha: 0.1),
                                foregroundColor: const Color(0xFF4F46E5),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Stable version input
                    TextField(
                      controller: _latestStableVersionController,
                      style: GoogleFonts.outfit(color: textColor),
                      decoration: InputDecoration(
                        labelText: 'Latest Stable Version (e.g. 1.10.26)',
                        labelStyle: GoogleFonts.outfit(color: subtextColor),
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF0F172A)
                            : const Color(0xFFF1F5F9),
                        prefixIcon: const Icon(
                          Icons.verified_rounded,
                          color: Color(0xFF10B981),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: cardBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFF10B981),
                            width: 1.8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Static version input
                    TextField(
                      controller: _latestStaticVersionController,
                      style: GoogleFonts.outfit(color: textColor),
                      decoration: InputDecoration(
                        labelText: 'Latest Static Version (e.g. 1.10.20)',
                        labelStyle: GoogleFonts.outfit(color: subtextColor),
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF0F172A)
                            : const Color(0xFFF1F5F9),
                        prefixIcon: const Icon(
                          Icons.push_pin_rounded,
                          color: Color(0xFFF59E0B),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: cardBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFFF59E0B),
                            width: 1.8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),

                    // Beta Testers Selection
                    Row(
                      children: [
                        const Icon(
                          Icons.group_work_rounded,
                          size: 18,
                          color: Color(0xFF6366F1),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Select Beta Testers',
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF6366F1,
                            ).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_selectedBetaTesterUids.length} selected',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF6366F1),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Users selected here will automatically receive beta builds as tags are pushed.',
                      style: GoogleFonts.outfit(
                        color: subtextColor,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 10),

                    _allUsers.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Text(
                              'No registered users found.',
                              style: GoogleFonts.outfit(
                                color: subtextColor,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          )
                        : Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _allUsers.map((user) {
                              final username = user['username']!;
                              final uid = user['uid']!;
                              final isChecked = _selectedBetaTesterUids
                                  .contains(uid);
                              return FilterChip(
                                label: Text(
                                  '@$username',
                                  style: GoogleFonts.outfit(
                                    color: isChecked
                                        ? Colors.white
                                        : (isDark
                                              ? Colors.white70
                                              : const Color(0xFF334155)),
                                    fontWeight: isChecked
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    fontSize: 12.5,
                                  ),
                                ),
                                selected: isChecked,
                                selectedColor: const Color(0xFF6366F1),
                                backgroundColor: isDark
                                    ? const Color(0xFF0F172A)
                                    : const Color(0xFFF1F5F9),
                                checkmarkColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                side: BorderSide(
                                  color: isChecked
                                      ? const Color(0xFF818CF8)
                                      : cardBorder,
                                ),
                                onSelected: (val) {
                                  setState(() {
                                    if (val) {
                                      _selectedBetaTesterUids.add(uid);
                                      _selectedStaticUserUids.remove(uid);
                                    } else {
                                      _selectedBetaTesterUids.remove(uid);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                    const SizedBox(height: 22),

                    // Static Users Selection
                    Row(
                      children: [
                        const Icon(
                          Icons.push_pin_rounded,
                          size: 18,
                          color: Color(0xFFF59E0B),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Select Static Users',
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFF59E0B,
                            ).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_selectedStaticUserUids.length} selected',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFFF59E0B),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Users selected here receive ONLY updates when Latest Static Version is bumped.',
                      style: GoogleFonts.outfit(
                        color: subtextColor,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 10),

                    Builder(
                      builder: (context) {
                        final staticEligibleUsers = _allUsers
                            .where(
                              (u) =>
                                  !_selectedBetaTesterUids.contains(u['uid']),
                            )
                            .toList();
                        if (staticEligibleUsers.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Text(
                              'No non-beta users available for static tier.',
                              style: GoogleFonts.outfit(
                                color: subtextColor,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          );
                        }
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: staticEligibleUsers.map((user) {
                            final username = user['username']!;
                            final uid = user['uid']!;
                            final isChecked = _selectedStaticUserUids.contains(
                              uid,
                            );
                            return FilterChip(
                              label: Text(
                                '@$username',
                                style: GoogleFonts.outfit(
                                  color: isChecked
                                      ? Colors.white
                                      : (isDark
                                            ? Colors.white70
                                            : const Color(0xFF334155)),
                                  fontWeight: isChecked
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  fontSize: 12.5,
                                ),
                              ),
                              selected: isChecked,
                              selectedColor: const Color(0xFFF59E0B),
                              backgroundColor: isDark
                                  ? const Color(0xFF0F172A)
                                  : const Color(0xFFF1F5F9),
                              checkmarkColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              side: BorderSide(
                                color: isChecked
                                    ? const Color(0xFFFBBF24)
                                    : cardBorder,
                              ),
                              onSelected: (val) {
                                setState(() {
                                  if (val) {
                                    _selectedStaticUserUids.add(uid);
                                  } else {
                                    _selectedStaticUserUids.remove(uid);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 24),

                    ElevatedButton.icon(
                      onPressed: _updateAppUpdatesConfig,
                      icon: const Icon(Icons.save_rounded, size: 18),
                      label: Text(
                        'Save Release Config',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: const Color(0xFF7C3AED),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
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
    );
  }

  Widget _buildAccountsTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF161E2E) : Colors.white;
    final cardBorder = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtextColor = isDark
        ? Colors.white60
        : const Color(0xFF64748B);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: cardBorder),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.3)
                      : Colors.black.withValues(alpha: 0.03),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(22.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header Row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.manage_accounts_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'User Accounts Manager',
                            style: GoogleFonts.outfit(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                          Text(
                            'Provision, reset credentials, or remove accounts',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              color: subtextColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Create new user profiles with collaboration authorization, change account passwords, or delete users completely.',
                  style: GoogleFonts.outfit(
                    color: subtextColor,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 20),

                // Username input
                TextField(
                  controller: _adminUserUsernameController,
                  style: GoogleFonts.outfit(color: textColor),
                  decoration: InputDecoration(
                    labelText: 'Target Username',
                    labelStyle: GoogleFonts.outfit(color: subtextColor),
                    hintText: 'e.g. roshan',
                    hintStyle: GoogleFonts.outfit(
                      color: subtextColor.withValues(alpha: 0.5),
                    ),
                    filled: true,
                    fillColor: isDark
                        ? const Color(0xFF0F172A)
                        : const Color(0xFFF1F5F9),
                    prefixIcon: const Icon(
                      Icons.person_rounded,
                      color: Color(0xFF3B82F6),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: cardBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: Color(0xFF3B82F6),
                        width: 1.8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Password input
                TextField(
                  controller: _adminUserPasswordController,
                  obscureText: true,
                  style: GoogleFonts.outfit(color: textColor),
                  decoration: InputDecoration(
                    labelText: 'Password / New Password',
                    labelStyle: GoogleFonts.outfit(color: subtextColor),
                    filled: true,
                    fillColor: isDark
                        ? const Color(0xFF0F172A)
                        : const Color(0xFFF1F5F9),
                    prefixIcon: const Icon(
                      Icons.lock_rounded,
                      color: Color(0xFF3B82F6),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: cardBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: Color(0xFF3B82F6),
                        width: 1.8,
                      ),
                    ),
                  ),
                ),

                // Success / Error Feedback
                if (_adminUserSuccessMessage.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF10B981),
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _adminUserSuccessMessage,
                            style: GoogleFonts.outfit(
                              color: const Color(0xFF10B981),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_adminUserErrorMessage.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Colors.redAccent,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _adminUserErrorMessage,
                            style: GoogleFonts.outfit(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 22),

                // Action Buttons
                _isAdminUserActionLoading
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12.0),
                          child: CircularProgressIndicator(
                            color: Color(0xFF4F46E5),
                          ),
                        ),
                      )
                    : Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        alignment: WrapAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4F46E5),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 13,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: _adminCreateUser,
                            icon: const Icon(
                              Icons.person_add_rounded,
                              size: 18,
                            ),
                            label: Text(
                              'Create User',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD97706),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 13,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: _adminChangePassword,
                            icon: const Icon(
                              Icons.lock_reset_rounded,
                              size: 18,
                            ),
                            label: Text(
                              'Reset Password',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 13,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: _adminDeleteUser,
                            icon: const Icon(
                              Icons.person_remove_rounded,
                              size: 18,
                            ),
                            label: Text(
                              'Delete User',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionsTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF161E2E) : Colors.white;
    final cardBorder = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtextColor = isDark
        ? Colors.white60
        : const Color(0xFF64748B);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4.0,
                  vertical: 4.0,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      size: 20,
                      color: Color(0xFF4F46E5),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'User Feature Permissions & Partner Authorization',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        color: textColor,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Text(
                  'Toggle module availability per user and configure authorized peer-to-peer collaboration.',
                  style: GoogleFonts.outfit(color: subtextColor, fontSize: 12.5),
                ),
              ),
              const SizedBox(height: 14),

              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('usernames')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40.0),
                        child: CircularProgressIndicator(
                          color: Color(0xFF4F46E5),
                        ),
                      ),
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Text(
                          'No registered users found.',
                          style: GoogleFonts.outfit(color: subtextColor),
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final usernameDoc = docs[index];
                      final username = usernameDoc.id;
                      final usernameData =
                          usernameDoc.data() as Map<String, dynamic>;
                      final userId = usernameData['uid'] ?? '';
                      final email = usernameData['email'] ?? '';

                      if (userId.isEmpty) return const SizedBox.shrink();

                      return StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(userId)
                            .snapshots(),
                        builder: (context, userSnap) {
                          final userData =
                              userSnap.data?.data() as Map<String, dynamic>?;
                          final enabledModules = List<String>.from(
                            userData?['enabledModules'] ?? [
                              'reminders',
                              'gold',
                              'notes',
                              'daily_reminders',
                            ],
                          );

                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 7),
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: cardBorder),
                              boxShadow: [
                                BoxShadow(
                                  color: isDark
                                      ? Colors.black.withValues(alpha: 0.2)
                                      : Colors.black.withValues(alpha: 0.02),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Theme(
                              data: Theme.of(context).copyWith(
                                dividerColor: Colors.transparent,
                              ),
                              child: ExpansionTile(
                                leading: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF6366F1),
                                        Color(0xFF8B5CF6),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFF6366F1,
                                        ).withValues(alpha: 0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Text(
                                      username.isNotEmpty
                                          ? username
                                                .substring(0, 1)
                                                .toUpperCase()
                                          : 'U',
                                      style: GoogleFonts.outfit(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Text(
                                      '@$username',
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15.5,
                                        color: textColor,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFF10B981,
                                        ).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '${enabledModules.length} Active',
                                        style: GoogleFonts.outfit(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                          color: const Color(0xFF10B981),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Text(
                                  email.isNotEmpty
                                      ? email
                                      : 'No email associated',
                                  style: GoogleFonts.outfit(
                                    fontSize: 12.5,
                                    color: subtextColor,
                                  ),
                                ),
                                children: [
                                  Divider(
                                    height: 1,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.07)
                                        : Colors.black.withValues(alpha: 0.05),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.extension_rounded,
                                          size: 18,
                                          color: Color(0xFF4F46E5),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Feature Permissions (16 Modules)',
                                          style: GoogleFonts.outfit(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13.5,
                                            color: const Color(0xFF4F46E5),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Compact Responsive Grid for Modules
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        final double width =
                                            constraints.maxWidth;
                                        final int cols = width > 750
                                            ? 3
                                            : (width > 480 ? 2 : 1);
                                        return GridView.builder(
                                          shrinkWrap: true,
                                          physics:
                                              const NeverScrollableScrollPhysics(),
                                          gridDelegate:
                                              SliverGridDelegateWithFixedCrossAxisCount(
                                                crossAxisCount: cols,
                                                crossAxisSpacing: 8,
                                                mainAxisSpacing: 8,
                                                childAspectRatio: cols == 1
                                                    ? 5.8
                                                    : 4.2,
                                              ),
                                          itemCount: _availableModules.length,
                                          itemBuilder: (context, idx) {
                                            final mod = _availableModules[idx];
                                            final modId =
                                                mod['id']! as String;
                                            final modLabel =
                                                mod['label']! as String;
                                            final modIcon =
                                                mod['icon'] as IconData;
                                            final modColor =
                                                mod['color'] as Color;
                                            final isEnabled = enabledModules
                                                .contains(modId);

                                            return Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: isEnabled
                                                    ? modColor.withValues(
                                                        alpha: isDark
                                                            ? 0.12
                                                            : 0.08,
                                                      )
                                                    : (isDark
                                                          ? const Color(
                                                              0xFF0F172A,
                                                            )
                                                          : const Color(
                                                              0xFFF8FAFC,
                                                            )),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: isEnabled
                                                      ? modColor.withValues(
                                                          alpha: 0.35,
                                                        )
                                                      : (isDark
                                                            ? Colors.white
                                                                .withValues(
                                                                  alpha: 0.05,
                                                                )
                                                            : Colors.black
                                                                .withValues(
                                                                  alpha: 0.05,
                                                                )),
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.all(6),
                                                    decoration: BoxDecoration(
                                                      color: modColor
                                                          .withValues(
                                                            alpha: 0.15,
                                                          ),
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: Icon(
                                                      modIcon,
                                                      size: 16,
                                                      color: modColor,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      modLabel,
                                                      style: GoogleFonts.outfit(
                                                        fontSize: 12.5,
                                                        fontWeight: isEnabled
                                                            ? FontWeight.bold
                                                            : FontWeight.w500,
                                                        color: isEnabled
                                                            ? textColor
                                                            : subtextColor,
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  Transform.scale(
                                                    scale: 0.8,
                                                    child: Switch(
                                                      value: isEnabled,
                                                      activeThumbColor: modColor,
                                                      activeTrackColor: modColor.withValues(alpha: 0.4),
                                                      onChanged: (val) =>
                                                          _toggleModule(
                                                            userId,
                                                            modId,
                                                            val,
                                                            enabledModules,
                                                          ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  ),

                                  const SizedBox(height: 12),
                                  Divider(
                                    height: 1,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.07)
                                        : Colors.black.withValues(alpha: 0.05),
                                  ),

                                  // Collaboration Partners Section
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.people_alt_rounded,
                                          size: 18,
                                          color: Color(0xFF8B5CF6),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Allowed Collaboration Partners',
                                          style: GoogleFonts.outfit(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13.5,
                                            color: const Color(0xFF8B5CF6),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 2,
                                    ),
                                    child: Text(
                                      'Select which registered users @$username can send collaboration requests to across all features.',
                                      style: GoogleFonts.outfit(
                                        fontSize: 11.5,
                                        color: subtextColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 6,
                                    ),
                                    child: Builder(
                                      builder: (context) {
                                        final allowedCollaborators =
                                            List<String>.from(
                                              userData?['allowedCollaborators'] ??
                                                  [],
                                            );
                                        final otherUsers = docs
                                            .where(
                                              (d) =>
                                                  d.id.toLowerCase() !=
                                                  username.toLowerCase(),
                                            )
                                            .toList();

                                        if (otherUsers.isEmpty) {
                                          return Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Text(
                                              'No other registered users available to authorize.',
                                              style: GoogleFonts.outfit(
                                                color: subtextColor,
                                                fontSize: 12,
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          );
                                        }

                                        return Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: otherUsers.map((otherDoc) {
                                            final otherUsername = otherDoc.id;
                                            final otherData =
                                                otherDoc.data()
                                                    as Map<String, dynamic>;
                                            final otherUid =
                                                (otherData['uid'] ?? '')
                                                    .toString();
                                            final isAllowed =
                                                allowedCollaborators.contains(
                                                  otherUsername,
                                                ) ||
                                                allowedCollaborators.contains(
                                                  otherUid,
                                                );

                                            return FilterChip(
                                              label: Text(
                                                '@$otherUsername',
                                                style: GoogleFonts.outfit(
                                                  color: isAllowed
                                                      ? Colors.white
                                                      : (isDark
                                                            ? Colors.white70
                                                            : const Color(
                                                                0xFF334155,
                                                              )),
                                                  fontWeight: isAllowed
                                                      ? FontWeight.bold
                                                      : FontWeight.w500,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              selected: isAllowed,
                                              selectedColor: const Color(
                                                0xFF7C3AED,
                                              ),
                                              backgroundColor: isDark
                                                  ? const Color(0xFF0F172A)
                                                  : const Color(0xFFF1F5F9),
                                              checkmarkColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              side: BorderSide(
                                                color: isAllowed
                                                    ? const Color(0xFF8B5CF6)
                                                    : cardBorder,
                                              ),
                                              onSelected: (val) =>
                                                  _toggleAllowedCollaborator(
                                                    userId,
                                                    otherUsername,
                                                    val,
                                                    allowedCollaborators,
                                                  ),
                                            );
                                          }).toList(),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
