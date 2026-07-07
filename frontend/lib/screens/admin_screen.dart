import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../services/encryption_service.dart';

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
    super.dispose();
  }

  Future<void> _checkLocalAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final isAuth = prefs.getBool('isAdminAuthenticated') ?? false;
    if (isAuth) {
      await _fetchGeminiApiKey();
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
                            children: _availableModules.map((mod) {
                              final modId = mod['id']!;
                              final modLabel = mod['label']!;
                              final isEnabled = enabledModules.contains(modId);

                              return SwitchListTile(
                                title: Text(modLabel),
                                value: isEnabled,
                                onChanged: (val) => _toggleModule(userId, modId, val, enabledModules),
                              );
                            }).toList(),
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
