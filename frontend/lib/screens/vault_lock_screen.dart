import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/encryption_service.dart';

class VaultLockScreen extends StatefulWidget {
  final VoidCallback onAuthenticated;

  const VaultLockScreen({super.key, required this.onAuthenticated});

  @override
  State<VaultLockScreen> createState() => _VaultLockScreenState();
}

class _VaultLockScreenState extends State<VaultLockScreen> {
  final _pinController = TextEditingController();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  bool _isLoading = true;
  bool _isFirstTimeSetup = false;
  String? _firstEnteredPin; // Used during setup confirmation
  String _errorMessage = '';

  String? _userSalt;
  String? _userVerifier;

  String? get _currentUid => _auth.currentUser?.uid;

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
    final uid = _currentUid;
    if (uid == null) {
      setState(() {
        _errorMessage = "User not authenticated.";
        _isLoading = false;
      });
      return;
    }

    try {
      // Check user-specific PIN config in Firestore
      final userPinDoc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('vault_config')
          .doc('pin')
          .get();

      if (userPinDoc.exists && userPinDoc.data() != null) {
        final data = userPinDoc.data()!;
        _userSalt = data['salt'];
        _userVerifier = data['verifier'];
        setState(() {
          _isFirstTimeSetup = false;
          _isLoading = false;
        });
      } else {
        // No PIN configured for this user -> First Time Setup
        setState(() {
          _isFirstTimeSetup = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Error checking vault config: $e";
        _isLoading = false;
      });
    }
  }

  Future<void> _handlePinSubmit(String pin) async {
    if (pin.length < 4) {
      setState(() => _errorMessage = "PIN must be at least 4 digits.");
      return;
    }

    if (_isFirstTimeSetup) {
      await _handleFirstTimeSetup(pin);
    } else {
      await _handleUnlock(pin);
    }
  }

  Future<void> _handleFirstTimeSetup(String pin) async {
    if (_firstEnteredPin == null) {
      // Step 1: First entry -> prompt confirmation
      setState(() {
        _firstEnteredPin = pin;
        _pinController.clear();
        _errorMessage = '';
      });
    } else {
      // Step 2: Confirmation
      if (pin != _firstEnteredPin) {
        setState(() {
          _firstEnteredPin = null;
          _pinController.clear();
          _errorMessage = "PINs do not match. Please enter your PIN again.";
        });
        return;
      }

      // Setup matches -> create salt & verifier and save to user's Firestore path
      setState(() => _isLoading = true);
      try {
        final uid = _currentUid;
        if (uid == null) throw Exception("User not authenticated.");

        final encryptionService = EncryptionService();
        final salt = encryptionService.generateSalt();

        encryptionService.setKeyFromPIN(pin, salt);
        final verifier = encryptionService.encryptVerifier();

        await _firestore
            .collection('users')
            .doc(uid)
            .collection('vault_config')
            .doc('pin')
            .set({
          'salt': salt,
          'verifier': verifier,
          'createdAt': FieldValue.serverTimestamp(),
        });

        widget.onAuthenticated();
      } catch (e) {
        setState(() {
          _errorMessage = "Failed to save Vault PIN: $e";
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleUnlock(String pin) async {
    setState(() => _isLoading = true);

    final encryptionService = EncryptionService();
    bool isCorrect = false;

    if (_userSalt != null && _userVerifier != null) {
      isCorrect = encryptionService.verifyDecryption(_userVerifier!, pin, _userSalt!);
    }

    if (isCorrect && _userSalt != null) {
      encryptionService.setKeyFromPIN(pin, _userSalt!);
      widget.onAuthenticated();
    } else {
      _pinController.clear();
      setState(() {
        _errorMessage = "Incorrect PIN. Access Denied.";
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

    String titleText = 'Enter Vault PIN';
    String subtitleText = 'Enter your 4-digit security PIN to unlock your vault.';
    String buttonText = 'Unlock Vault';

    if (_isFirstTimeSetup) {
      if (_firstEnteredPin == null) {
        titleText = 'Create Vault PIN';
        subtitleText = 'Set a 4 to 6 digit Security PIN to protect your private documents.';
        buttonText = 'Next: Confirm PIN';
      } else {
        titleText = 'Confirm Vault PIN';
        subtitleText = 'Re-enter your 4-digit PIN to confirm.';
        buttonText = 'Set PIN & Unlock';
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('🔒 Vault Security'),
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
                _isFirstTimeSetup ? Icons.lock_reset_rounded : Icons.lock_person_outlined,
                size: 80,
                color: Colors.blueAccent,
              ),
              const SizedBox(height: 24),
              Text(
                titleText,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                subtitleText,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
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
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage,
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const Spacer(),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () => _handlePinSubmit(_pinController.text),
                child: Text(buttonText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
