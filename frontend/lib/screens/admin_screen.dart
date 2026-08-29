import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:share_plus/share_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
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

  final List<Map<String, String>> _availableModules = [
    {'id': 'gold', 'label': 'Gold Rates'},
    {'id': 'gold_chit', 'label': 'Gold Chit Tracker'},
    {'id': 'reminders', 'label': 'Calendar Reminders'},
    {'id': 'daily_reminders', 'label': 'Daily Reminders'},
    {'id': 'notes', 'label': 'Aesthetic Notes'},
    {'id': 'shifts', 'label': 'My Shifts'},
    {'id': 'job_assistant', 'label': 'AI Job Assistant'},
    {'id': 'finance', 'label': 'Finance & Split Expenses'},
    {'id': 'checklist', 'label': 'Checklist'},
    {'id': 'vault', 'label': 'Secure Vault'},
    {'id': 'events', 'label': 'Tech Events'},
    {'id': 'walkin', 'label': 'Walk-In Drives'},
    {'id': 'voice_assistant', 'label': 'Voice Assistant'},
    {'id': 'ask_gemini', 'label': 'Ask Gemini Buttons'},
    {'id': 'gcp_cost', 'label': 'GCP Cost Tracker'},
    {'id': 'astro_calendar', 'label': 'Astro Calendar'},
    {'id': 'sms_study', 'label': 'SMS Study Sync (15 Days)'},
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
    if (isAuth) {
      await _fetchGeminiApiKey();
      await _fetchAppUpdatesConfig();
    }
    setState(() {
      _isAuthenticated = isAuth;
      _isLoading = false;
    });
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
        final key = doc.data()!['apiKey'] ?? '';
        _geminiApiKeyController.text = key;
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
      final usernamesSnap = await FirebaseFirestore.instance.collection('usernames').get();
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
    final key = _geminiApiKeyController.text.trim();
    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance
          .collection('admin_creds')
          .doc('gemini_config')
          .set({
        'apiKey': key,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        _geminiApiKeySuccessMessage = 'Gemini API Key updated successfully!';
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
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update Gemini API Key: $e')),
        );
      }
    }
  }

  Future<void> _updateAppUpdatesConfig() async {
    setState(() => _isLoading = true);

    // Map selected UIDs back to usernames for storage
    final List<String> betaUsernames = [];
    for (var uid in _selectedBetaTesterUids) {
      final userMap = _allUsers.firstWhere((u) => u['uid'] == uid, orElse: () => {});
      if (userMap.isNotEmpty && userMap['username'] != null) {
        betaUsernames.add(userMap['username']!);
      }
    }

    final List<String> staticUsernames = [];
    for (var uid in _selectedStaticUserUids) {
      final userMap = _allUsers.firstWhere((u) => u['uid'] == uid, orElse: () => {});
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
        'latest_beta_version': _latestGitHubBetaVersion.isNotEmpty ? _latestGitHubBetaVersion : '1.6.9', // fallback
        'beta_tester_uids': _selectedBetaTesterUids,
        'beta_tester_usernames': betaUsernames,
        'static_user_uids': _selectedStaticUserUids,
        'static_user_usernames': staticUsernames,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('App Updates configuration saved!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update config: $e')),
        );
      }
    }
  }


  Future<void> _toggleModule(String userId, String moduleId, bool enable, List<String> enabledModules) async {
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
          SnackBar(content: Text('Error updating user permissions: ${e.toString().replaceAll("Exception:", "")}')),
        );
      }
    }
  }

  Future<void> _adminCreateUser() async {
    final username = _adminUserUsernameController.text.trim();
    final password = _adminUserPasswordController.text.trim();
    if (username.isEmpty || password.isEmpty) {
      setState(() => _adminUserErrorMessage = 'Username and password are required.');
      return;
    }
    if (password.length < 6) {
      setState(() => _adminUserErrorMessage = 'Password must be at least 6 characters.');
      return;
    }

    // Fetch existing usernames for the collaboration partner pop-up
    final usernamesSnap = await FirebaseFirestore.instance.collection('usernames').get();
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
          final List<String> tempSelected = List.from(existingUsernames);
          return StatefulBuilder(
            builder: (context, setPopState) {
              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Row(
                  children: [
                    const Icon(Icons.people_alt, color: Colors.purple),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Allowed Partners for @$username',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                      const Text(
                        'Select which existing users this new user is authorized to collaborate with:',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: () {
                              setPopState(() {
                                tempSelected.clear();
                                tempSelected.addAll(existingUsernames);
                              });
                            },
                            child: const Text('Select All', style: TextStyle(fontSize: 12)),
                          ),
                          TextButton(
                            onPressed: () {
                              setPopState(() {
                                tempSelected.clear();
                              });
                            },
                            child: const Text('Deselect All', style: TextStyle(fontSize: 12, color: Colors.red)),
                          ),
                        ],
                      ),
                      const Divider(height: 12),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: existingUsernames.map((u) {
                              final isChecked = tempSelected.contains(u);
                              return FilterChip(
                                label: Text('@$u'),
                                selected: isChecked,
                                selectedColor: Colors.purple.shade100,
                                checkmarkColor: Colors.purple,
                                onSelected: (val) {
                                  setPopState(() {
                                    if (val) {
                                      if (!tempSelected.contains(u)) tempSelected.add(u);
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
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade800,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.pop(context, tempSelected),
                    icon: const Icon(Icons.check),
                    label: const Text('Create User'),
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
        _adminUserSuccessMessage = 'User "$username" created with ${selectedPartners.length} allowed partner(s)!';
        _isAdminUserActionLoading = false;
      });
    } catch (e) {
      setState(() {
        _adminUserErrorMessage = 'Failed to create user: ${e.toString().replaceAll("Exception:", "")}';
        _isAdminUserActionLoading = false;
      });
    }
  }

  Future<void> _adminChangePassword() async {
    final username = _adminUserUsernameController.text.trim();
    final password = _adminUserPasswordController.text.trim();
    if (username.isEmpty || password.isEmpty) {
      setState(() => _adminUserErrorMessage = 'Username and new password are required.');
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
        _adminUserSuccessMessage = 'Password updated for user "$username"!';
        _isAdminUserActionLoading = false;
      });
    } catch (e) {
      setState(() {
        _adminUserErrorMessage = 'Failed to change password: ${e.toString().replaceAll("Exception:", "")}';
        _isAdminUserActionLoading = false;
      });
    }
  }

  Future<void> _adminDeleteUser() async {
    final username = _adminUserUsernameController.text.trim();
    if (username.isEmpty) {
      setState(() => _adminUserErrorMessage = 'Username is required to delete a user.');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: Text('Are you sure you want to permanently delete user "$username" and all their settings? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
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
        _adminUserErrorMessage = 'Failed to delete user: ${e.toString().replaceAll("Exception:", "")}';
        _isAdminUserActionLoading = false;
      });
    }
  }

  Future<void> _toggleAllowedCollaborator(String userId, String targetUsername, bool allow, List<String> currentAllowed) async {
    final updatedList = List<String>.from(currentAllowed);
    if (allow) {
      if (!updatedList.contains(targetUsername)) updatedList.add(targetUsername);
    } else {
      updatedList.remove(targetUsername);
    }

    try {
      try {
        final callable = FirebaseFunctions.instance.httpsCallable('adminUpdateAllowedCollaborators');
        await callable.call({
          'userId': userId,
          'allowedCollaborators': updatedList,
        });
      } catch (_) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .set({
          'allowedCollaborators': updatedList,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating allowed collaborators: $e')),
        );
      }
    }
  }

  bool _isSharingApk = false;

  Future<void> _shareLatestApk() async {
    if (_isSharingApk) return;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final version = packageInfo.version;

      if (!kIsWeb) {
        // 1. Check if an APK already exists locally in temp cache
        final tempDir = await getTemporaryDirectory();
        final cachedApk = File('${tempDir.path}/RemindBuddy-v$version.apk');
        if (await cachedApk.exists() && (await cachedApk.length()) > 5000000) {
          await Share.shareXFiles(
            [XFile(cachedApk.path)],
            text: '📥 RemindBuddy App APK (v$version)',
            subject: 'RemindBuddy App APK',
          );
          return;
        }

        // 2. Otherwise download latest release APK from Firebase Storage
        setState(() => _isSharingApk = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                  SizedBox(width: 12),
                  Text('Downloading latest APK to share...'),
                ],
              ),
              duration: Duration(seconds: 5),
            ),
          );
        }

        const firebaseApkUrl = 'https://firebasestorage.googleapis.com/v0/b/remindbuddy-b68f9.firebasestorage.app/o/releases%2Flatest-release.apk?alt=media';
        final response = await http.get(Uri.parse(firebaseApkUrl));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          await cachedApk.writeAsBytes(response.bodyBytes);
          await Share.shareXFiles(
            [XFile(cachedApk.path)],
            text: '📥 RemindBuddy App APK (v$version)',
            subject: 'RemindBuddy App APK',
          );
          return;
        }
      }

      // Fallback if web or network failed
      const firebaseApkUrl = 'https://firebasestorage.googleapis.com/v0/b/remindbuddy-b68f9.firebasestorage.app/o/releases%2Flatest-release.apk?alt=media';
      final shareText = '''
📱 *RemindBuddy App (v${packageInfo.version})*
Download latest release APK:
$firebaseApkUrl
'''.trim();

      await Share.share(shareText, subject: 'Download RemindBuddy App APK');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error preparing APK for sharing: $e'),
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
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isAuthenticated) {
      return _buildLoginScreen();
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('⚙️ Admin Control Panel', style: TextStyle(fontWeight: FontWeight.bold)),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: _shareLatestApk,
              tooltip: 'Share App APK',
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _handleLogout,
              tooltip: 'Logout Admin',
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.tune), text: 'System Config'),
              Tab(icon: Icon(Icons.manage_accounts), text: 'User Accounts'),
              Tab(icon: Icon(Icons.security), text: 'Permissions'),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Console Login'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.admin_panel_settings_outlined, size: 90, color: Colors.blueGrey),
              const SizedBox(height: 16),
              const Text(
                'Access Restricted',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter Administrator Credentials to access feature toggles.',
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.lock),
                ),
              ),
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage,
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _handleLogin,
                child: const Text('Login', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConfigTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section 1.5: Gemini API Configuration
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '🤖 Gemini AI Configuration',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Provide your Google Gemini API Key from Google AI Studio. This is used securely in Cloud Functions to parse roster images.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _geminiApiKeyController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Gemini API Key',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _updateGeminiApiKey,
                        child: const Text('Save Key'),
                      ),
                    ],
                  ),
                  if (_geminiApiKeySuccessMessage.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _geminiApiKeySuccessMessage,
                      style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Section 1.8: App Updates & Release Management
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '🚀 App Updates & Rollouts',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Control which versions of the app are promoted to stable (all users) versus beta (testers only).',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  
                  // Beta version info (auto-fetched from GitHub)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.bug_report, color: Colors.orange, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Latest Beta Version (GitHub)',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              const SizedBox(height: 2),
                              _isFetchingGithub
                                  ? const SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Text(
                                      _latestGitHubBetaVersion.isNotEmpty
                                          ? _latestGitHubBetaVersion
                                          : 'Not found',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ],
                          ),
                        ),
                        if (_latestGitHubBetaVersion.isNotEmpty)
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _latestStableVersionController.text = _latestGitHubBetaVersion;
                              });
                            },
                            icon: const Icon(Icons.copy, size: 16),
                            label: const Text('Promote to Stable'),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Stable version input
                  TextField(
                    controller: _latestStableVersionController,
                    decoration: const InputDecoration(
                      labelText: 'Latest Stable Version (e.g. 1.6.0)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.verified),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Static version input
                  TextField(
                    controller: _latestStaticVersionController,
                    decoration: const InputDecoration(
                      labelText: 'Latest Static Version (e.g. 1.5.0)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.push_pin_outlined),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Checkbox list of Beta Testers
                  const Text(
                    '👥 Select Beta Testers',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Check users who should receive beta updates automatically.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  _allUsers.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            'No registered users found.',
                            style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                          ),
                        )
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _allUsers.map((user) {
                            final username = user['username']!;
                            final uid = user['uid']!;
                            final isChecked = _selectedBetaTesterUids.contains(uid);
                            return FilterChip(
                              label: Text(username),
                              selected: isChecked,
                              onSelected: (val) {
                                setState(() {
                                  if (val) {
                                    _selectedBetaTesterUids.add(uid);
                                    // Remove from static if added to beta
                                    _selectedStaticUserUids.remove(uid);
                                  } else {
                                    _selectedBetaTesterUids.remove(uid);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                  const SizedBox(height: 20),

                  // Checkbox list of Static Users (Excluding Beta Testers)
                  const Text(
                    '📌 Select Static Users',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Users selected here receive ONLY updates when Latest Static Version is updated.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final staticEligibleUsers = _allUsers.where((u) => !_selectedBetaTesterUids.contains(u['uid'])).toList();
                      if (staticEligibleUsers.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            'No non-beta users available for static tier.',
                            style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                          ),
                        );
                      }
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: staticEligibleUsers.map((user) {
                          final username = user['username']!;
                          final uid = user['uid']!;
                          final isChecked = _selectedStaticUserUids.contains(uid);
                          return FilterChip(
                            label: Text(username),
                            selected: isChecked,
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
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _updateAppUpdatesConfig,
                    icon: const Icon(Icons.save),
                    label: const Text('Save Release Config'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '👥 User Accounts Manager',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Create new users, change passwords, or delete users completely.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _adminUserUsernameController,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _adminUserPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password / New Password',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.lock),
                    ),
                  ),
                  if (_adminUserSuccessMessage.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      _adminUserSuccessMessage,
                      style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                    ),
                  ],
                  if (_adminUserErrorMessage.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      _adminUserErrorMessage,
                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _isAdminUserActionLoading
                      ? const Center(child: CircularProgressIndicator())
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.spaceEvenly,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue.shade800,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: _adminCreateUser,
                              icon: const Icon(Icons.person_add),
                              label: const Text('Create'),
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange.shade800,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: _adminChangePassword,
                              icon: const Icon(Icons.lock_reset),
                              label: const Text('Reset Pass'),
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade800,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: _adminDeleteUser,
                              icon: const Icon(Icons.person_remove),
                              label: const Text('Delete'),
                            ),
                          ],
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
            child: Text(
              '👤 Manage Feature Permissions per User',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 16),
            ),
          ),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('usernames').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: CircularProgressIndicator(),
                ));
              }

              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Text('No registered users found.'),
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
                  final usernameData = usernameDoc.data() as Map<String, dynamic>;
                  final userId = usernameData['uid'] ?? '';
                  final email = usernameData['email'] ?? '';

                  if (userId.isEmpty) return const SizedBox.shrink();

                  return StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance.collection('users').doc(userId).snapshots(),
                    builder: (context, userSnap) {
                      final userData = userSnap.data?.data() as Map<String, dynamic>?;
                      final enabledModules = List<String>.from(userData?['enabledModules'] ?? ['gold']);

                      return Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: ExpansionTile(
                          leading: const Icon(Icons.account_circle, color: Colors.blueGrey),
                          title: Text(
                            username,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(email.isNotEmpty ? email : 'No email associated'),
                          children: [
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Row(
                                children: [
                                  Icon(Icons.extension, size: 18, color: Colors.blueAccent),
                                  SizedBox(width: 8),
                                  Text(
                                    'Feature Permissions',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueAccent),
                                  ),
                                ],
                              ),
                            ),
                            // Compact Responsive Grid for Modules
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final double width = constraints.maxWidth;
                                final int cols = width > 750 ? 3 : (width > 500 ? 2 : 1);
                                return GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: cols,
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 2,
                                    childAspectRatio: cols == 1 ? 5.5 : 4.0,
                                  ),
                                  itemCount: _availableModules
                                      .where((mod) => !kIsWeb || mod['id'] != 'checklist')
                                      .length,
                                  itemBuilder: (context, idx) {
                                    final filteredMods = _availableModules
                                        .where((mod) => !kIsWeb || mod['id'] != 'checklist')
                                        .toList();
                                    final mod = filteredMods[idx];
                                    final modId = mod['id']!;
                                    final modLabel = mod['label']!;
                                    final isEnabled = enabledModules.contains(modId);

                                    return SwitchListTile(
                                      title: Text(modLabel, style: const TextStyle(fontSize: 12)),
                                      value: isEnabled,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                                      onChanged: (val) => _toggleModule(userId, modId, val, enabledModules),
                                    );
                                  },
                                );
                              },
                            ),
                            const Divider(),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Row(
                                children: [
                                  Icon(Icons.people_alt, size: 18, color: Colors.purple),
                                  SizedBox(width: 8),
                                  Text(
                                    'Allowed Collaboration Partners (Admin Authorized)',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.purple),
                                  ),
                                ],
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                              child: Text(
                                'Select which users this user can send collaboration requests to across all features.',
                                style: TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Builder(
                                builder: (context) {
                                  final allowedCollaborators = List<String>.from(userData?['allowedCollaborators'] ?? []);
                                  final otherUsers = docs.where((d) => d.id.toLowerCase() != username.toLowerCase()).toList();

                                  if (otherUsers.isEmpty) {
                                    return const Padding(
                                      padding: EdgeInsets.all(12.0),
                                      child: Text('No other registered users to authorize.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                    );
                                  }

                                  return Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: otherUsers.map((otherDoc) {
                                      final otherUsername = otherDoc.id;
                                      final otherData = otherDoc.data() as Map<String, dynamic>;
                                      final otherUid = (otherData['uid'] ?? '').toString();
                                      final isAllowed = allowedCollaborators.contains(otherUsername) || allowedCollaborators.contains(otherUid);

                                      return FilterChip(
                                        label: Text('@$otherUsername'),
                                        selected: isAllowed,
                                        onSelected: (val) => _toggleAllowedCollaborator(
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
                            const SizedBox(height: 12),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
