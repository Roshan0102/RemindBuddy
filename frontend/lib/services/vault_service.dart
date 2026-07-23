import 'dart:async';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/secure_document.dart';
import '../models/vault_collaborator.dart';
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
  // USERNAME & COLLABORATION METHODS
  // ==========================================

  /// Fetch current logged-in user's username
  Future<String> getCurrentUsername() async {
    final user = _auth.currentUser;
    if (user == null) return '';
    try {
      final snap = await _firestore
          .collection('usernames')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        return snap.docs.first.id;
      }
    } catch (e) {
      print("VaultService: Error fetching username: $e");
    }
    return user.displayName ?? user.email ?? 'Myself';
  }

  /// Stream of active collaborators for the current user (includes current user as self)
  Stream<List<VaultCollaborator>> getVaultCollaborators() {
    final uid = _currentUserId;
    if (uid == null) return Stream.value([]);

    late StreamController<List<VaultCollaborator>> controller;
    StreamSubscription? sub1;
    StreamSubscription? sub2;

    List<VaultCollaborator> list1 = [];
    List<VaultCollaborator> list2 = [];

    Future<void> emitCollaborators() async {
      final String myUsername = await getCurrentUsername();
      final String myEmail = _auth.currentUser?.email ?? '';

      final selfMember = VaultCollaborator(
        uid: uid,
        username: myUsername.isNotEmpty ? myUsername : 'Myself',
        email: myEmail,
        collaborationId: 'self',
        isSelf: true,
        avatarColorValue: VaultCollaborator.generateColorForUser(myUsername),
      );

      final Map<String, VaultCollaborator> map = {uid: selfMember};

      for (var c in list1) {
        map[c.uid] = c;
      }
      for (var c in list2) {
        map[c.uid] = c;
      }

      if (!controller.isClosed) {
        controller.add(map.values.toList());
      }
    }

    controller = StreamController<List<VaultCollaborator>>.broadcast(
      onListen: () {
        // Emit initial self user immediately so StreamBuilder connectionState becomes active without waiting!
        emitCollaborators();

        // Query 1: Requests sent by me that were approved
        sub1 = _firestore
            .collection('vault_collaborations')
            .where('senderUid', isEqualTo: uid)
            .where('status', isEqualTo: 'approved')
            .snapshots()
            .listen((snap) {
          list1 = snap.docs.map((doc) {
            final data = doc.data();
            final receiverUid = (data['receiverUid'] ?? '').toString();
            final receiverUsername = (data['receiverUsername'] ?? 'User').toString();
            return VaultCollaborator(
              uid: receiverUid,
              username: receiverUsername,
              email: '',
              collaborationId: doc.id,
              isSelf: false,
              avatarColorValue: VaultCollaborator.generateColorForUser(receiverUsername),
            );
          }).toList();
          emitCollaborators();
        }, onError: (e) {
          print("VaultService: Error listening to sent collabs: $e");
          emitCollaborators();
        });

        // Query 2: Requests received by me that were approved
        sub2 = _firestore
            .collection('vault_collaborations')
            .where('receiverUid', isEqualTo: uid)
            .where('status', isEqualTo: 'approved')
            .snapshots()
            .listen((snap) {
          list2 = snap.docs.map((doc) {
            final data = doc.data();
            final senderUid = (data['senderUid'] ?? '').toString();
            final senderUsername = (data['senderUsername'] ?? 'User').toString();
            return VaultCollaborator(
              uid: senderUid,
              username: senderUsername,
              email: '',
              collaborationId: doc.id,
              isSelf: false,
              avatarColorValue: VaultCollaborator.generateColorForUser(senderUsername),
            );
          }).toList();
          emitCollaborators();
        }, onError: (e) {
          print("VaultService: Error listening to received collabs: $e");
          emitCollaborators();
        });
      },
      onCancel: () {
        sub1?.cancel();
        sub2?.cancel();
      },
    );

    return controller.stream;
  }

  /// Stream of incoming pending collaboration requests
  Stream<List<VaultCollaborationRequest>> getIncomingRequestsStream() {
    final uid = _currentUserId;
    if (uid == null) return Stream.value([]);

    return _firestore
        .collection('vault_collaborations')
        .where('receiverUid', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.docs.map((d) => VaultCollaborationRequest.fromMap(d.id, d.data())).toList());
  }

  /// Stream of outgoing pending collaboration requests
  Stream<List<VaultCollaborationRequest>> getOutgoingRequestsStream() {
    final uid = _currentUserId;
    if (uid == null) return Stream.value([]);

    return _firestore
        .collection('vault_collaborations')
        .where('senderUid', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.docs.map((d) => VaultCollaborationRequest.fromMap(d.id, d.data())).toList());
  }

  /// Send a vault collaboration request to another registered app user
  Future<void> sendVaultCollaborationRequest(String targetUsername) async {
    final uid = _currentUserId;
    if (uid == null) throw Exception("User not authenticated.");

    final cleanUsername = targetUsername.trim();
    if (cleanUsername.isEmpty) throw Exception("Please enter a username.");

    final myUsername = await getCurrentUsername();
    if (cleanUsername.toLowerCase() == myUsername.toLowerCase()) {
      throw Exception("You cannot send a collaboration request to yourself.");
    }

    // Lookup user in usernames collection
    final userSnap = await _firestore
        .collection('usernames')
        .doc(cleanUsername)
        .get();

    String receiverUid = '';
    String receiverUsername = cleanUsername;

    if (userSnap.exists) {
      receiverUid = (userSnap.data()?['uid'] ?? '').toString();
      receiverUsername = userSnap.id;
    } else {
      final querySnap = await _firestore.collection('usernames').get();
      final matchedDoc = querySnap.docs.firstWhere(
        (doc) => doc.id.toLowerCase() == cleanUsername.toLowerCase(),
        orElse: () => throw Exception("User '@$cleanUsername' not found."),
      );
      receiverUid = (matchedDoc.data()['uid'] ?? '').toString();
      receiverUsername = matchedDoc.id;
    }

    if (receiverUid.isEmpty) {
      throw Exception("User '@$cleanUsername' does not have a valid account ID.");
    }

    if (receiverUid == uid) {
      throw Exception("You cannot send a collaboration request to yourself.");
    }

    // Check admin-configured allowedCollaborators restriction for current user
    try {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      if (userDoc.exists && userDoc.data() != null && userDoc.data()!.containsKey('allowedCollaborators')) {
        final allowed = List<String>.from(userDoc.data()!['allowedCollaborators'] ?? []);
        if (!allowed.contains(receiverUid) && !allowed.contains(receiverUsername) && !allowed.contains(cleanUsername)) {
          throw Exception("Admin restriction: You are not authorized to send collaboration requests to @$cleanUsername.");
        }
      }
    } catch (e) {
      if (e.toString().contains("Admin restriction")) rethrow;
    }

    // Check if collaboration or request already exists (2 separate queries for Security Rules compliance)
    final sentSnap = await _firestore
        .collection('vault_collaborations')
        .where('senderUid', isEqualTo: uid)
        .where('receiverUid', isEqualTo: receiverUid)
        .get();

    final receivedSnap = await _firestore
        .collection('vault_collaborations')
        .where('senderUid', isEqualTo: receiverUid)
        .where('receiverUid', isEqualTo: uid)
        .get();

    final existingDocs = [...sentSnap.docs, ...receivedSnap.docs];

    for (var doc in existingDocs) {
      final data = doc.data();
      final status = data['status'];

      if (status == 'approved') {
        throw Exception("You are already collaborating with @$receiverUsername.");
      } else if (status == 'pending') {
        throw Exception("A collaboration request with @$receiverUsername is already pending.");
      }
    }

    await _firestore.collection('vault_collaborations').add({
      'senderUid': uid,
      'senderUsername': myUsername,
      'receiverUid': receiverUid,
      'receiverUsername': receiverUsername,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Respond to a pending vault collaboration request (Accept or Reject)
  Future<void> respondToVaultCollaborationRequest(String requestId, bool approve) async {
    final uid = _currentUserId;
    if (uid == null) throw Exception("User not authenticated.");

    final ref = _firestore.collection('vault_collaborations').doc(requestId);
    if (approve) {
      await ref.update({'status': 'approved'});
    } else {
      await ref.delete();
    }
  }

  /// Remove an active vault collaborator
  Future<void> removeVaultCollaborator(String collaborationId) async {
    final uid = _currentUserId;
    if (uid == null) throw Exception("User not authenticated.");

    await _firestore.collection('vault_collaborations').doc(collaborationId).delete();
  }

  // ==========================================
  // SECURE DOCUMENT METHODS
  // ==========================================

  /// Stream of raw (encrypted) secure documents from current user AND all approved collaborators
  Stream<List<SecureDocument>> getSecureDocuments() {
    final uid = _currentUserId;
    if (uid == null) return Stream.value([]);

    late StreamController<List<SecureDocument>> controller;
    StreamSubscription? collabSub;
    final Map<String, StreamSubscription> docSubs = {};
    final Map<String, List<SecureDocument>> docsPerUser = {};

    void emitMerged() {
      final List<SecureDocument> combined = [];
      for (var list in docsPerUser.values) {
        combined.addAll(list);
      }
      combined.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
      if (!controller.isClosed) {
        controller.add(combined);
      }
    }

    controller = StreamController<List<SecureDocument>>.broadcast(
      onListen: () {
        emitMerged();
        collabSub = getVaultCollaborators().listen((collaborators) {
          final Set<String> targetUids = {uid, ...collaborators.map((c) => c.uid)};

          // Cancel subscriptions for users no longer in target list
          docSubs.keys.toList().forEach((userUid) {
            if (!targetUids.contains(userUid)) {
              docSubs[userUid]?.cancel();
              docSubs.remove(userUid);
              docsPerUser.remove(userUid);
            }
          });

          // Subscribe to document streams for new users
          for (final userUid in targetUids) {
            if (!docSubs.containsKey(userUid)) {
              docSubs[userUid] = _firestore
                  .collection('users')
                  .doc(userUid)
                  .collection('secure_documents')
                  .snapshots()
                  .listen((snap) {
                docsPerUser[userUid] = snap.docs.map((d) => SecureDocument.fromMap(d.data())).toList();
                emitMerged();
              }, onError: (e) {
                print("VaultService: Error listening to secure_documents for $userUid: $e");
              });
            }
          }
          emitMerged();
        });
      },
      onCancel: () {
        collabSub?.cancel();
        for (var sub in docSubs.values) {
          sub.cancel();
        }
        docSubs.clear();
        docsPerUser.clear();
      },
    );

    return controller.stream;
  }

  /// Stream of unique category names from existing documents across user and collaborators
  Stream<List<String>> getExistingCategories() {
    return getSecureDocuments().map((docs) {
      final Set<String> categories = {};
      for (var d in docs) {
        if (d.category.trim().isNotEmpty) {
          categories.add(d.category.trim());
        }
      }
      return categories.toList()..sort();
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

  /// Save or update a document locally encrypted
  Future<void> saveDocument({
    String? id,
    required String memberId, // Owner UID
    required String ownerName,
    required String category,
    required String title,
    required Map<String, String> fields,
    required List<Uint8List> rawImagesToUpload,
    required List<String> newAttachmentsNames,
    required List<String> existingAttachmentPaths,
  }) async {
    final uid = _currentUserId;
    if (uid == null) throw Exception("User not authenticated.");

    final encryptionService = EncryptionService();

    final encryptedTitle = await encryptionService.encryptText(title);

    final Map<String, String> encryptedFields = {};
    for (var entry in fields.entries) {
      if (entry.value.isNotEmpty) {
        encryptedFields[entry.key] = await encryptionService.encryptText(entry.value);
      }
    }

    final targetUid = memberId.isNotEmpty ? memberId : uid;

    final docId = id ?? _firestore
        .collection('users')
        .doc(targetUid)
        .collection('secure_documents')
        .doc()
        .id;

    final List<String> uploadedPaths = [...existingAttachmentPaths];
    for (int i = 0; i < rawImagesToUpload.length; i++) {
      final imageBytes = rawImagesToUpload[i];
      final encryptedBytes = await encryptionService.encryptBytes(imageBytes);

      final originalName = newAttachmentsNames[i];
      final ext = originalName.contains('.') ? originalName.split('.').last : 'bin';
      
      final safeOwner = ownerName.replaceAll(RegExp(r'[^\w\-_]'), '_');
      final safeTitle = title.replaceAll(RegExp(r'[^\w\-_]'), '_');
      
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storagePath = 'users/$targetUid/vault_attachments/$docId/${safeOwner}_-_${safeTitle}_${timestamp}_$i.$ext';
      
      final ref = _storage.ref().child(storagePath);
      await ref.putData(
        encryptedBytes,
        SettableMetadata(contentType: 'application/octet-stream'),
      );
      
      uploadedPaths.add(storagePath);
    }

    final doc = SecureDocument(
      id: docId,
      memberId: targetUid,
      category: category,
      encryptedTitle: encryptedTitle,
      encryptedFields: encryptedFields,
      encryptedAttachmentPaths: uploadedPaths,
      lastUpdated: DateTime.now(),
    );

    await _firestore
        .collection('users')
        .doc(targetUid)
        .collection('secure_documents')
        .doc(docId)
        .set(doc.toMap());
  }

  /// Delete a secure document and all its associated encrypted attachments from Storage
  Future<void> deleteDocument(SecureDocument doc) async {
    final uid = _currentUserId;
    if (uid == null) throw Exception("User not authenticated.");

    final targetUid = doc.memberId.isNotEmpty ? doc.memberId : uid;

    for (var path in doc.encryptedAttachmentPaths) {
      try {
        await _storage.ref().child(path).delete();
      } catch (e) {
        print("VaultService: Error deleting attachment $path: $e");
      }
    }

    await _firestore
        .collection('users')
        .doc(targetUid)
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
