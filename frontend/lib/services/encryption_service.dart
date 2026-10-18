import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  enc.Key? _sessionKey;
  enc.Key? _familyKey;
  final List<enc.Key> _fallbackKeys = [];

  /// Returns true if a decryption key is loaded in volatile RAM.
  bool get hasKey => _sessionKey != null;

  /// Active session key
  enc.Key? get sessionKey => _sessionKey;

  /// Shared Family key (if user is in a family)
  enc.Key? get familyKey => _familyKey;

  /// Sets the family shared encryption key and adds to fallback keys
  void setFamilyKey(String familyKeyB64) {
    try {
      final bytes = base64Url.decode(familyKeyB64);
      _familyKey = enc.Key(Uint8List.fromList(bytes));
      addFallbackKey(_familyKey!);
    } catch (e) {
      debugPrint("EncryptionService: Failed to parse familyKey: $e");
    }
  }

  /// Clear the memory-only key (e.g., when locking the vault or app going background).
  void clearKey() {
    _sessionKey = null;
    _familyKey = null;
    _fallbackKeys.clear();
  }

  /// Add a secondary or shared key (e.g., family key or previous PIN key for recovery)
  void addFallbackKey(enc.Key key) {
    if (!_fallbackKeys.any((k) => listEquals(k.bytes, key.bytes))) {
      _fallbackKeys.add(key);
    }
  }

  /// Sets the symmetric key derived directly from the user's PIN and salt (legacy mode).
  void setKeyFromPIN(String pin, String salt) {
    _sessionKey = deriveKeyFromPIN(pin, salt);
  }

  /// Sets the active session key directly from a 32-byte Vault Master Key.
  void setSessionKeyFromMasterKey(String masterKeyB64) {
    final bytes = base64Url.decode(masterKeyB64);
    _sessionKey = enc.Key(Uint8List.fromList(bytes));
  }

  /// Derives a Key Encryption Key (KEK) from PIN and salt using 5,000 SHA-256 rounds.
  enc.Key deriveKeyFromPIN(String pin, String salt) {
    List<int> bytes = utf8.encode(pin + salt);
    for (int i = 0; i < 5000; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return enc.Key(Uint8List.fromList(bytes));
  }

  /// Generate a cryptographically random 256-bit Vault Master Key.
  String generateMasterKey() {
    final random = Random.secure();
    final keyBytes = Uint8List.fromList(
      List<int>.generate(32, (i) => random.nextInt(256)),
    );
    return base64Url.encode(keyBytes);
  }

  /// Encrypts the Vault Master Key with the user's PIN-derived KEK.
  String encryptMasterKey(String masterKeyB64, enc.Key kek) {
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(kek, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(masterKeyB64, iv: iv);

    final combinedBytes = Uint8List(iv.bytes.length + encrypted.bytes.length);
    combinedBytes.setRange(0, iv.bytes.length, iv.bytes);
    combinedBytes.setRange(iv.bytes.length, combinedBytes.length, encrypted.bytes);

    return base64Url.encode(combinedBytes);
  }

  /// Decrypts the Vault Master Key with the user's PIN-derived KEK.
  String? decryptMasterKey(String encryptedMasterKey, enc.Key kek) {
    try {
      final combinedBytes = base64Url.decode(encryptedMasterKey);
      if (combinedBytes.length <= 16) return null;

      final ivBytes = combinedBytes.sublist(0, 16);
      final cipherBytes = combinedBytes.sublist(16);

      final iv = enc.IV(ivBytes);
      final encrypter = enc.Encrypter(enc.AES(kek, mode: enc.AESMode.cbc));
      return encrypter.decrypt(enc.Encrypted(cipherBytes), iv: iv);
    } catch (e) {
      debugPrint("EncryptionService: Decrypt master key failed: $e");
      return null;
    }
  }

  /// Generate a cryptographically random salt to store in Firestore for this user.
  String generateSalt() {
    final random = Random.secure();
    final saltBytes = Uint8List.fromList(
      List<int>.generate(16, (i) => random.nextInt(256)),
    );
    return base64Url.encode(saltBytes);
  }

  /// Helper to encrypt a verifier string to check PIN correctness using active session key.
  String encryptVerifier() {
    if (_sessionKey == null) throw Exception("Session key not initialized.");
    return encryptVerifierWithKey(_sessionKey!);
  }

  /// Encrypts verifier string using an explicit key (e.g. KEK derived from PIN).
  String encryptVerifierWithKey(enc.Key key) {
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt("VERIFIER", iv: iv);

    final combinedBytes = Uint8List(iv.bytes.length + encrypted.bytes.length);
    combinedBytes.setRange(0, iv.bytes.length, iv.bytes);
    combinedBytes.setRange(iv.bytes.length, combinedBytes.length, encrypted.bytes);

    return base64Url.encode(combinedBytes);
  }

  /// Verifies if a given verifier string decrypts correctly to "VERIFIER".
  bool verifyDecryption(String encryptedVerifier, String pin, String salt) {
    final tempKey = deriveKeyFromPIN(pin, salt);
    try {
      final combinedBytes = base64Url.decode(encryptedVerifier);
      if (combinedBytes.length <= 16) return false;

      final ivBytes = combinedBytes.sublist(0, 16);
      final cipherBytes = combinedBytes.sublist(16);

      final iv = enc.IV(ivBytes);
      final encrypter = enc.Encrypter(enc.AES(tempKey, mode: enc.AESMode.cbc));

      final decrypted = encrypter.decrypt(enc.Encrypted(cipherBytes), iv: iv);
      return decrypted == "VERIFIER";
    } catch (_) {
      return false;
    }
  }

  /// Encrypts plain text using AES-256 in CBC mode with a random IV.
  /// Accepts optional [customKey] (e.g., shared family key), otherwise defaults to active [sessionKey].
  Future<String> encryptText(String plainText, {enc.Key? customKey}) async {
    if (plainText.isEmpty) return '';
    final key = customKey ?? _sessionKey;
    if (key == null) throw Exception("Vault is locked. Key not loaded in memory.");

    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

    final encrypted = encrypter.encrypt(plainText, iv: iv);

    final combinedBytes = Uint8List(iv.bytes.length + encrypted.bytes.length);
    combinedBytes.setRange(0, iv.bytes.length, iv.bytes);
    combinedBytes.setRange(iv.bytes.length, combinedBytes.length, encrypted.bytes);

    return base64Url.encode(combinedBytes);
  }

  /// Decrypts a Base64 encoded string containing [16-byte IV + Ciphertext].
  /// Attempts active session key first, then gracefully falls back to secondary/family keys.
  Future<String> decryptText(String encryptedBase64) async {
    if (encryptedBase64.isEmpty) return '';
    if (_sessionKey == null && _fallbackKeys.isEmpty) {
      throw Exception("Vault is locked. Key not loaded in memory.");
    }

    final candidateKeys = <enc.Key>[];
    if (_sessionKey != null) candidateKeys.add(_sessionKey!);
    candidateKeys.addAll(_fallbackKeys);

    for (final key in candidateKeys) {
      try {
        final combinedBytes = base64Url.decode(encryptedBase64);
        if (combinedBytes.length <= 16) continue;

        final ivBytes = combinedBytes.sublist(0, 16);
        final cipherBytes = combinedBytes.sublist(16);

        final iv = enc.IV(ivBytes);
        final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

        final decrypted = encrypter.decrypt(enc.Encrypted(cipherBytes), iv: iv);
        return decrypted;
      } catch (_) {
        // Try next candidate key
      }
    }

    debugPrint("EncryptionService: All candidate keys failed to decrypt text.");
    return "[Decryption Error]";
  }

  /// Encrypts raw binary data (e.g., image bytes) using AES-256 with a random IV.
  /// Accepts optional [customKey] (e.g., shared family key), otherwise defaults to active [sessionKey].
  Future<Uint8List> encryptBytes(Uint8List plainBytes, {enc.Key? customKey}) async {
    if (plainBytes.isEmpty) return Uint8List(0);
    final key = customKey ?? _sessionKey;
    if (key == null) throw Exception("Vault is locked. Key not loaded in memory.");

    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

    final encrypted = encrypter.encryptBytes(plainBytes, iv: iv);

    final combinedBytes = Uint8List(iv.bytes.length + encrypted.bytes.length);
    combinedBytes.setRange(0, iv.bytes.length, iv.bytes);
    combinedBytes.setRange(iv.bytes.length, combinedBytes.length, encrypted.bytes);

    return combinedBytes;
  }

  /// Decrypts a byte array containing [16-byte IV + Ciphertext].
  /// Tries session key, then fallback keys.
  Future<Uint8List> decryptBytes(Uint8List encryptedBytes) async {
    if (encryptedBytes.isEmpty) return Uint8List(0);
    if (_sessionKey == null && _fallbackKeys.isEmpty) {
      throw Exception("Vault is locked. Key not loaded in memory.");
    }

    final candidateKeys = <enc.Key>[];
    if (_sessionKey != null) candidateKeys.add(_sessionKey!);
    candidateKeys.addAll(_fallbackKeys);

    for (final key in candidateKeys) {
      try {
        if (encryptedBytes.length <= 16) continue;

        final ivBytes = encryptedBytes.sublist(0, 16);
        final cipherBytes = encryptedBytes.sublist(16);

        final iv = enc.IV(ivBytes);
        final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

        final decryptedList = encrypter.decryptBytes(enc.Encrypted(cipherBytes), iv: iv);
        return Uint8List.fromList(decryptedList);
      } catch (_) {
        // Try next candidate key
      }
    }

    debugPrint("EncryptionService: All candidate keys failed to decrypt bytes.");
    return Uint8List(0);
  }
}
