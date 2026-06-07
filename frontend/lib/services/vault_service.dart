import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/family_member.dart';
import '../models/secure_document.dart';
import 'encryption_service.dart';

class DecryptedDocument {
  final SecureDocument original;
  final String title;
  final Map<String, String> fields;

  DecryptedDocument({
    required this.original,
    required this.title,
    required this.fields,
  });
}

class VaultService {
  static final VaultService _instance = VaultService._internal();
  factory VaultService() => _instance;
  VaultService._internal();

  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final _auth = FirebaseAuth.instance;

  String? get _currentUserId => _auth.currentUser?.uid;

  // ==========================================
  // FAMILY MEMBER METHODS
  // ==========================================

  /// Stream of family members for the current user
  Stream<List<FamilyMember>> getFamilyMembers() {
    final uid = _currentUserId;
    if (uid == null) return Stream.value([]);

    return _firestore
        .collection('users')
        .doc(uid)
        .collection('family_members')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => FamilyMember.fromMap(doc.data())).toList();
    });
  }

  /// Add a family member
  Future<void> addFamilyMember(String name, String relationship, int avatarColorValue) async {
    final uid = _currentUserId;
    if (uid == null) throw Exception("User not authenticated.");

    final docRef = _firestore
        .collection('users')
        .doc(uid)
        .collection('family_members')
        .doc();

    final member = FamilyMember(
      id: docRef.id,
      name: name,
      relationship: relationship,
      avatarColorValue: avatarColorValue,
    );

    await docRef.set(member.toMap());
  }

  /// Update a family member
  Future<void> updateFamilyMember(FamilyMember member) async {
    final uid = _currentUserId;
    if (uid == null) throw Exception("User not authenticated.");

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('family_members')
        .doc(member.id)
        .update(member.toMap());
  }

  /// Delete a family member and their documents
  Future<void> deleteFamilyMember(String memberId) async {
    final uid = _currentUserId;
    if (uid == null) throw Exception("User not authenticated.");

    // Delete all documents belonging to this family member
    final docsSnap = await _firestore
        .collection('users')
        .doc(uid)
        .collection('secure_documents')
        .where('memberId', isEqualTo: memberId)
        .get();

    for (var doc in docsSnap.docs) {
      final secureDoc = SecureDocument.fromMap(doc.data());
      await deleteDocument(secureDoc);
    }

    // Delete the family member record
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('family_members')
        .doc(memberId)
        .delete();
  }

  // ==========================================
  // SECURE DOCUMENT METHODS
  // ==========================================

  /// Stream of raw (encrypted) secure documents
  Stream<List<SecureDocument>> getSecureDocuments() {
    final uid = _currentUserId;
    if (uid == null) return Stream.value([]);

    return _firestore
        .collection('users')
        .doc(uid)
        .collection('secure_documents')
        .orderBy('lastUpdated', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => SecureDocument.fromMap(doc.data())).toList();
    });
  }

  /// Decrypt a single document into memory
  Future<DecryptedDocument> decryptDocument(SecureDocument doc) async {
    final encryptionService = EncryptionService();
    
    final decryptedTitle = await encryptionService.decryptText(doc.encryptedTitle);
    
    final Map<String, String> decryptedFields = {};
    for (var entry in doc.encryptedFields.entries) {
      final decryptedValue = await encryptionService.decryptText(entry.value);
      decryptedFields[entry.key] = decryptedValue;
    }

    return DecryptedDocument(
      original: doc,
      title: decryptedTitle,
      fields: decryptedFields,
    );
  }

  /// Save or update a document
  /// Encrypts all fields and titles locally and uploads encrypted image bytes to Storage.
  Future<void> saveDocument({
    String? id,
    required String memberId,
    required String category,
    required String title,
    required Map<String, String> fields,
    required List<Uint8List> rawImagesToUpload,
    required List<String> existingAttachmentPaths,
  }) async {
    final uid = _currentUserId;
    if (uid == null) throw Exception("User not authenticated.");

    final encryptionService = EncryptionService();

    // 1. Encrypt Title
    final encryptedTitle = await encryptionService.encryptText(title);

    // 2. Encrypt Custom Fields
    final Map<String, String> encryptedFields = {};
    for (var entry in fields.entries) {
      if (entry.value.isNotEmpty) {
        encryptedFields[entry.key] = await encryptionService.encryptText(entry.value);
      }
    }

    // 3. Resolve Document ID
    final docId = id ?? _firestore
        .collection('users')
        .doc(uid)
        .collection('secure_documents')
        .doc()
        .id;

    // 4. Encrypt and Upload New Attachments
    final List<String> uploadedPaths = [...existingAttachmentPaths];
    for (int i = 0; i < rawImagesToUpload.length; i++) {
      final imageBytes = rawImagesToUpload[i];
      final encryptedBytes = await encryptionService.encryptBytes(imageBytes);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storagePath = 'users/$uid/vault_attachments/$docId/${timestamp}_$i.bin';
      
      final ref = _storage.ref().child(storagePath);
      // Upload as octet-stream for raw bytes
      await ref.putData(
        encryptedBytes,
        SettableMetadata(contentType: 'application/octet-stream'),
      );
      
      uploadedPaths.add(storagePath);
    }

    // 5. Save SecureDocument Model in Firestore
    final doc = SecureDocument(
      id: docId,
      memberId: memberId,
      category: category,
      encryptedTitle: encryptedTitle,
      encryptedFields: encryptedFields,
      encryptedAttachmentPaths: uploadedPaths,
      lastUpdated: DateTime.now(),
    );

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('secure_documents')
        .doc(docId)
        .set(doc.toMap());
  }

  /// Delete a secure document and all its associated encrypted attachments from Storage
  Future<void> deleteDocument(SecureDocument doc) async {
    final uid = _currentUserId;
    if (uid == null) throw Exception("User not authenticated.");

    // Delete attachments from storage
    for (var path in doc.encryptedAttachmentPaths) {
      try {
        await _storage.ref().child(path).delete();
      } catch (e) {
        print("VaultService: Error deleting attachment $path: $e");
      }
    }

    // Delete Firestore document record
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('secure_documents')
        .doc(doc.id)
        .delete();
  }

  /// Downloads and decrypts an image attachment
  Future<Uint8List?> downloadAndDecryptAttachment(String storagePath) async {
    try {
      final ref = _storage.ref().child(storagePath);
      final encryptedBytes = await ref.getData(10 * 1024 * 1024); // max 10MB
      
      if (encryptedBytes == null) return null;

      final decryptedBytes = await EncryptionService().decryptBytes(encryptedBytes);
      return decryptedBytes;
    } catch (e) {
      print("VaultService: Error downloading/decrypting attachment: $e");
      return null;
    }
  }
}
