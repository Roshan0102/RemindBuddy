import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../services/encryption_service.dart';
import '../services/update_service.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _vaultPinController = TextEditingController();
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
  String _vaultPinSuccessMessage = '';
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
    {'id': 'checklist', 'label': 'Checklist'},
    {'id': 'vault', 'label': 'Secure Vault'},
    {'id': 'events', 'label': 'Tech Events'},
    {'id': 'walkin', 'label': 'Walk-In Drives'},
    {'id': 'voice_assistant', 'label': 'Voice Assistant'},
    {'id': 'ask_gemini', 'label': 'Ask Gemini Buttons'},
    {'id': 'gcp_cost', 'label': 'GCP Cost Tracker'},
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
    _vaultPinController.dispose();
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
      print('Error fetching Gemini API key: $e');
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
      print('Error fetching App Updates config: $e');
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

  Future<void> _updateVaultMasterPin() async {
    final pin = _vaultPinController.text.trim();
    if (pin.length < 4 || pin.length > 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN must be between 4 and 6 digits.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final encryptionService = EncryptionService();
      final salt = encryptionService.generateSalt();
      
      // Temporarily set key to encrypt verifier
      encryptionService.setKeyFromPIN(pin, salt);
      final verifierCiphertext = encryptionService.encryptVerifier();
      encryptionService.clearKey(); // Clear the derived session key from RAM

      await FirebaseFirestore.instance
          .collection('admin_creds')
          .doc('vault_config')
          .set({
        'salt': salt,
        'verifier': verifierCiphertext,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _vaultPinController.clear();
      setState(() {
        _vaultPinSuccessMessage = 'Master PIN updated successfully!';
        _isLoading = false;
      });

      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _vaultPinSuccessMessage = '';
          });
        }
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update Master PIN: $e')),
      );
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
    setState(() {
      _isAdminUserActionLoading = true;
      _adminUserErrorMessage = '';
      _adminUserSuccessMessage = '';
    });
    try {
      await FirebaseFunctions.instance
          .httpsCallable('adminCreateUser')
          .call({'username': username, 'password': password});
      
      _adminUserUsernameController.clear();
      _adminUserPasswordController.clear();
      setState(() {
        _adminUserSuccessMessage = 'User "$username" created successfully!';
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
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .set({
        'allowedCollaborators': updatedList,
      }, SetOptions(merge: true));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating allowed collaborators: $e')),
        );
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

    return _buildAdminPanel();
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

  Widget _buildAdminPanel() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚙️ Admin Control Panel'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _handleLogout,
            tooltip: 'Logout Admin',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Section 1: Master PIN setup
            Card(
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '🔑 Vault Master PIN',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Set the single global Master PIN that users must enter to decrypt the secure vault.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _vaultPinController,
                            obscureText: true,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            decoration: const InputDecoration(
                              labelText: 'New Master PIN',
                              counterText: '',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: _updateVaultMasterPin,
                          child: const Text('Set PIN'),
                        ),
                      ],
                    ),
                    if (_vaultPinSuccessMessage.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _vaultPinSuccessMessage,
                        style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Section 1.5: Gemini API Configuration
            Card(
              margin: const EdgeInsets.all(16),
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

            // Section 1.8: App Updates & Release Management
            Card(
              margin: const EdgeInsets.all(16),
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
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _allUsers.length,
                            itemBuilder: (context, idx) {
                              final user = _allUsers[idx];
                              final username = user['username']!;
                              final uid = user['uid']!;
                              final isChecked = _selectedBetaTesterUids.contains(uid);
                              return CheckboxListTile(
                                title: Text(username),
                                subtitle: Text(
                                  uid,
                                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                                ),
                                value: isChecked,
                                dense: true,
                                controlAffinity: ListTileControlAffinity.leading,
                                contentPadding: EdgeInsets.zero,
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      _selectedBetaTesterUids.add(uid);
                                      // Remove from static if added to beta
                                      _selectedStaticUserUids.remove(uid);
                                    } else {
                                      _selectedBetaTesterUids.remove(uid);
                                    }
                                  });
                                },
                              );
                            },
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
                        return ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: staticEligibleUsers.length,
                          itemBuilder: (context, idx) {
                            final user = staticEligibleUsers[idx];
                            final username = user['username']!;
                            final uid = user['uid']!;
                            final isChecked = _selectedStaticUserUids.contains(uid);
                            return CheckboxListTile(
                              title: Text(username),
                              subtitle: Text(
                                uid,
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                              value: isChecked,
                              dense: true,
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedStaticUserUids.add(uid);
                                  } else {
                                    _selectedStaticUserUids.remove(uid);
                                  }
                                });
                              },
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 16),
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

            // Section 2: User Accounts Management
            Card(
              margin: const EdgeInsets.all(16),
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

            // Section 3: User List Feature control
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
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
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                              ..._availableModules
                                  .where((mod) => !kIsWeb || mod['id'] != 'checklist')
                                  .map((mod) {
                                final modId = mod['id']!;
                                final modLabel = mod['label']!;
                                final isEnabled = enabledModules.contains(modId);

                                return SwitchListTile(
                                  title: Text(modLabel),
                                  value: isEnabled,
                                  onChanged: (val) => _toggleModule(userId, modId, val, enabledModules),
                                );
                              }).toList(),
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
                                  'Select which users this user can send collaboration requests to across all features (Vault, Notes, Checklists, Calendar).',
                                  style: TextStyle(fontSize: 11, color: Colors.grey),
                                ),
                              ),
                              Builder(
                                builder: (context) {
                                  final allowedCollaborators = List<String>.from(userData?['allowedCollaborators'] ?? []);
                                  final otherUsers = docs.where((d) => d.id.toLowerCase() != username.toLowerCase()).toList();

                                  if (otherUsers.isEmpty) {
                                    return const Padding(
                                      padding: EdgeInsets.all(12.0),
                                      child: Text('No other registered users to authorize.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                    );
                                  }

                                  return Column(
                                    children: otherUsers.map((otherDoc) {
                                      final otherUsername = otherDoc.id;
                                      final otherData = otherDoc.data() as Map<String, dynamic>;
                                      final otherUid = (otherData['uid'] ?? '').toString();
                                      final isAllowed = allowedCollaborators.contains(otherUsername) || allowedCollaborators.contains(otherUid);

                                      return CheckboxListTile(
                                        title: Text('@$otherUsername'),
                                        subtitle: Text(otherData['email'] ?? ''),
                                        value: isAllowed,
                                        dense: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                                        onChanged: (val) => _toggleAllowedCollaborator(
                                          userId,
                                          otherUsername,
                                          val ?? false,
                                          allowedCollaborators,
                                        ),
                                      );
                                    }).toList(),
                                  );
                                },
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
      ),
    );
  }
}
