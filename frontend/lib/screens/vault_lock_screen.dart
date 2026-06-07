import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/encryption_service.dart';

class VaultLockScreen extends StatefulWidget {
  final VoidCallback onAuthenticated;

  const VaultLockScreen({super.key, required this.onAuthenticated});

  @override
  State<VaultLockScreen> createState() => _VaultLockScreenState();
}

class _VaultLockScreenState extends State<VaultLockScreen> {
  final _pinController = TextEditingController();
  bool _isLoading = true;
  bool _isConfigured = false;
  String _errorMessage = '';

  String? _salt;
  String? _verifier;

  @override
  void initState() {
    super.initState();
    _checkVaultConfig();
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _checkVaultConfig() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('admin_creds')
          .doc('vault_config')
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        _salt = data['salt'];
        _verifier = data['verifier'];
        setState(() {
          _isConfigured = true;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isConfigured = false;
          _errorMessage = "The Secure Vault is not configured.\nPlease ask the administrator to set up the Master PIN.";
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Error contacting Firestore: $e";
        _isLoading = false;
      });
    }
  }

  Future<void> _handlePinSubmit(String pin) async {
    if (!_isConfigured) return;

    if (pin.length < 4) {
      setState(() => _errorMessage = "PIN must be at least 4 digits.");
      return;
    }

    setState(() => _isLoading = true);

    if (_salt == null || _verifier == null) {
      setState(() {
        _errorMessage = "Configuration is corrupted. Please contact the administrator.";
        _isLoading = false;
      });
      return;
    }

    final encryptionService = EncryptionService();
    final isCorrect = encryptionService.verifyDecryption(_verifier!, pin, _salt!);

    if (isCorrect) {
      encryptionService.setKeyFromPIN(pin, _salt!);
      widget.onAuthenticated();
    } else {
      _pinController.clear();
      setState(() {
        _errorMessage = "Incorrect Master PIN. Access Denied.";
        _isLoading = false;
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('🔒 Vault Authorization'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                _isConfigured ? Icons.lock_person_outlined : Icons.report_problem_outlined,
                size: 80,
                color: _isConfigured ? Colors.blueAccent : Colors.amber,
              ),
              const SizedBox(height: 24),
              Text(
                _isConfigured ? 'Enter Master PIN' : 'Vault Not Configured',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                _isConfigured
                    ? 'Your decryption key is derived in RAM using the global Master PIN to unlock your secure files.'
                    : 'The administrator has not initialized the vault settings yet.',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (_isConfigured) ...[
                TextField(
                  controller: _pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  autofocus: true,
                  style: const TextStyle(fontSize: 32, letterSpacing: 16, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    counterText: '',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                    hintText: '••••',
                    hintStyle: const TextStyle(color: Colors.grey, letterSpacing: 4),
                  ),
                  onSubmitted: _handlePinSubmit,
                ),
              ],
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage,
                  style: TextStyle(
                    color: _isConfigured ? Colors.red : Colors.orange.shade800,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const Spacer(),
              if (_isConfigured) ...[
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => _handlePinSubmit(_pinController.text),
                  child: const Text('Unlock Vault'),
                ),
              ] else ...[
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    backgroundColor: Colors.grey,
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Go Back'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
