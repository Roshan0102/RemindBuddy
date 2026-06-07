import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  
  bool _isAuthenticated = false;
  bool _isLoading = true;
  String _errorMessage = '';
  String _vaultPinSuccessMessage = '';

  final List<Map<String, String>> _availableModules = [
    {'id': 'gold', 'label': 'Gold Rates'},
    {'id': 'reminders', 'label': 'Calendar Reminders'},
    {'id': 'notes', 'label': 'Aesthetic Notes'},
    {'id': 'shifts', 'label': 'My Shifts'},
    {'id': 'checklist', 'label': 'Checklist'},
    {'id': 'vault', 'label': 'Secure Vault'},
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
    super.dispose();
  }

  Future<void> _checkLocalAuth() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isAuthenticated = prefs.getBool('isAdminAuthenticated') ?? false;
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
    });
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
      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'enabledModules': newModules,
      }, SetOptions(merge: true));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating user permissions: $e')),
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

            // Section 2: User List Feature control
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text(
                '👤 Manage Feature Permissions per User',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 16),
              ),
            ),

            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').snapshots(),
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
                    final userDoc = docs[index];
                    final userId = userDoc.id;
                    final userData = userDoc.data() as Map<String, dynamic>;

                    final email = userData['email'] ?? userData['name'] ?? 'User ID: $userId';
                    final enabledModules = List<String>.from(userData['enabledModules'] ?? ['gold']);

                    return Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: ExpansionTile(
                        leading: const Icon(Icons.account_circle, color: Colors.blueGrey),
                        title: Text(
                          email,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: const Text('Tap to expand module settings'),
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
            ),
          ],
        ),
      ),
    );
  }
}
