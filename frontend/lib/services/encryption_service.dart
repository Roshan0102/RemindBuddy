import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  enc.Key? _sessionKey;

  /// Returns true if a decryption key is loaded in volatile RAM.
  bool get hasKey => _sessionKey != null;

  /// Clear the memory-only key (e.g., when locking the vault or app going background).
  void clearKey() {
    _sessionKey = null;
  }

  /// Sets the symmetric key derived from the user's PIN and a salt.
  /// Uses 5,000 iterations of SHA-256 stretching for brute-force resistance.
  void setKeyFromPIN(String pin, String salt) {
    List<int> bytes = utf8.encode(pin + salt);
    for (int i = 0; i < 5000; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    _sessionKey = enc.Key(Uint8List.fromList(bytes));
  }

  /// Generate a cryptographically random salt to store in Firestore for this user.
  String generateSalt() {
    final random = Random.secure();
    final saltBytes = Uint8List.fromList(
      List<int>.generate(16, (i) => random.nextInt(256)),
    );
    return base64Url.encode(saltBytes);
  }

  /// Helper to encrypt a verifier string to check PIN correctness.
  /// Encrypts the plain text "VERIFIER" using the current session key.
  String encryptVerifier() {
    if (_sessionKey == null) throw Exception("Session key not initialized.");
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(_sessionKey!, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt("VERIFIER", iv: iv);
    
    final combinedBytes = Uint8List(iv.bytes.length + encrypted.bytes.length);
    combinedBytes.setRange(0, iv.bytes.length, iv.bytes);
    combinedBytes.setRange(iv.bytes.length, combinedBytes.length, encrypted.bytes);

    return base64Url.encode(combinedBytes);
  }

  /// Verifies if a given verifier string decrypts correctly to "VERIFIER" using the temporary derived key.
  bool verifyDecryption(String encryptedVerifier, String pin, String salt) {
    // 1. Temporarily derive key
    List<int> bytes = utf8.encode(pin + salt);
    for (int i = 0; i < 5000; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    final tempKey = enc.Key(Uint8List.fromList(bytes));

    // 2. Attempt decryption
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
  /// Returns a Base64 encoded string containing [16-byte IV + Ciphertext].
  Future<String> encryptText(String plainText) async {
    if (plainText.isEmpty) return '';
    if (_sessionKey == null) throw Exception("Vault is locked. Key not loaded in memory.");

    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(_sessionKey!, mode: enc.AESMode.cbc));
    
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    
    final combinedBytes = Uint8List(iv.bytes.length + encrypted.bytes.length);
    combinedBytes.setRange(0, iv.bytes.length, iv.bytes);
    combinedBytes.setRange(iv.bytes.length, combinedBytes.length, encrypted.bytes);

    return base64Url.encode(combinedBytes);
  }

  /// Decrypts a Base64 encoded string containing [16-byte IV + Ciphertext].
  /// Returns the decrypted plain text.
  Future<String> decryptText(String encryptedBase64) async {
    if (encryptedBase64.isEmpty) return '';
    if (_sessionKey == null) throw Exception("Vault is locked. Key not loaded in memory.");

    try {
      final combinedBytes = base64Url.decode(encryptedBase64);
      if (combinedBytes.length <= 16) {
        throw Exception("Invalid cipher text length.");
      }

      final ivBytes = combinedBytes.sublist(0, 16);
      final cipherBytes = combinedBytes.sublist(16);

      final iv = enc.IV(ivBytes);
      final encrypter = enc.Encrypter(enc.AES(_sessionKey!, mode: enc.AESMode.cbc));
      
      final decrypted = encrypter.decrypt(enc.Encrypted(cipherBytes), iv: iv);
      return decrypted;
    } catch (e) {
      print("EncryptionService: Decryption failed: $e");
      return "[Decryption Error]";
    }
  }

  /// Encrypts raw binary data (e.g., image bytes) using AES-256 with a random IV.
  /// Returns a byte array containing [16-byte IV + Ciphertext].
  Future<Uint8List> encryptBytes(Uint8List plainBytes) async {
    if (plainBytes.isEmpty) return Uint8List(0);
    if (_sessionKey == null) throw Exception("Vault is locked. Key not loaded in memory.");

    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(_sessionKey!, mode: enc.AESMode.cbc));
    
    final encrypted = encrypter.encryptBytes(plainBytes, iv: iv);
    
    final combinedBytes = Uint8List(iv.bytes.length + encrypted.bytes.length);
    combinedBytes.setRange(0, iv.bytes.length, iv.bytes);
    combinedBytes.setRange(iv.bytes.length, combinedBytes.length, encrypted.bytes);

    return combinedBytes;
  }

  /// Decrypts a byte array containing [16-byte IV + Ciphertext].
  /// Returns the decrypted raw bytes.
  Future<Uint8List> decryptBytes(Uint8List encryptedBytes) async {
    if (encryptedBytes.isEmpty) return Uint8List(0);
    if (_sessionKey == null) throw Exception("Vault is locked. Key not loaded in memory.");

    try {
      if (encryptedBytes.length <= 16) {
        throw Exception("Invalid encrypted bytes length.");
      }

      final ivBytes = encryptedBytes.sublist(0, 16);
      final cipherBytes = encryptedBytes.sublist(16);

      final iv = enc.IV(ivBytes);
      final encrypter = enc.Encrypter(enc.AES(_sessionKey!, mode: enc.AESMode.cbc));
      
      final decryptedList = encrypter.decryptBytes(enc.Encrypted(cipherBytes), iv: iv);
      return Uint8List.fromList(decryptedList);
    } catch (e) {
      print("EncryptionService: Decrypt bytes failed: $e");
      return Uint8List(0);
    }
  }
}
