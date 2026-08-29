import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/secure_document.dart';
import '../models/vault_collaborator.dart';
import '../models/family_member.dart';
import '../models/vault_member_profile.dart';
import '../models/vault_family.dart';
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
  // VAULT FAMILY & SHARED ACCESS METHODS
  // ==========================================

  /// Stream of current user's active family (if any)
  Stream<VaultFamily?> getFamilyStream() {
    final uid = _currentUserId;
    if (uid == null) return Stream.value(null);

    return _firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .asyncExpand((userSnap) {
      if (!userSnap.exists || userSnap.data() == null) return Stream.value(null);
      final familyId = (userSnap.data()!['familyId'] ?? '').toString();
      if (familyId.isEmpty) return Stream.value(null);

      return _firestore
          .collection('families')
          .doc(familyId)
          .snapshots()
          .map((famSnap) {
        if (!famSnap.exists || famSnap.data() == null) return null;
        return VaultFamily.fromMap(famSnap.id, famSnap.data()!);
      });
    });
  }

  /// Stream of pending family invites for current user
  Stream<List<Map<String, dynamic>>> getPendingFamilyInvitesStream() {
    final uid = _currentUserId;
    if (uid == null) return Stream.value([]);

    return _firestore
        .collection('families')
        .snapshots()
        .map((snap) {
      final List<Map<String, dynamic>> invites = [];
      for (var doc in snap.docs) {
        final data = doc.data();
        final pending = List<Map<String, dynamic>>.from(data['pendingInvites'] ?? []);
        for (var p in pending) {
          if (p['uid'] == uid) {
            invites.add({
              'familyId': doc.id,
              'familyName': data['name'] ?? 'Family',
              'senderUsername': p['senderUsername'] ?? 'User',
              'senderUid': p['senderUid'] ?? '',
            });
          }
        }
      }
      return invites;
    });
  }

  /// Create a new family
  Future<void> createFamily(String familyName) async {
    final uid = _currentUserId;
    if (uid == null) throw Exception("User not authenticated.");

    final userDoc = await _firestore.collection('users').doc(uid).get();
    final existingFamilyId = (userDoc.data()?['familyId'] ?? '').toString();
    if (existingFamilyId.isNotEmpty) {
      throw Exception("You are already a member of a family. You cannot create multiple families.");
    }

    final docRef = _firestore.collection('families').doc();

    final familyData = {
      'id': docRef.id,
      'name': familyName.trim(),
      'adminUids': [uid],
      'collaboratorUids': [uid],
      'pendingInvites': [],
      'virtualProfiles': [],
      'createdAt': FieldValue.serverTimestamp(),
    };

    await docRef.set(familyData);
    await _firestore.collection('users').doc(uid).set({'familyId': docRef.id}, SetOptions(merge: true));
  }

  /// Fetch username for any given user UID
  Future<String> getUsernameByUid(String targetUid) async {
    if (targetUid.isEmpty) return 'User';
    try {
      final snap = await _firestore
          .collection('usernames')
          .where('uid', isEqualTo: targetUid)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        return snap.docs.first.id;
      }
    } catch (_) {}
    try {
      final uDoc = await _firestore.collection('users').doc(targetUid).get();
      if (uDoc.exists && uDoc.data() != null) {
        final data = uDoc.data()!;
        final uname = (data['username'] ?? data['displayName'] ?? data['email'] ?? '').toString();
        if (uname.isNotEmpty) return uname;
      }
    } catch (_) {}
    return targetUid;
  }

  /// Invite an app user to the family by username
  Future<void> inviteToFamily(String familyId, String targetUsername) async {
    final uid = _currentUserId;
    if (uid == null) throw Exception("User not authenticated.");

    final familySnap = await _firestore.collection('families').doc(familyId).get();
    if (!familySnap.exists) throw Exception("Family not found.");
    final familyData = familySnap.data()!;

    final adminUids = List<String>.from(familyData['adminUids'] ?? []);
    if (!adminUids.contains(uid)) {
      throw Exception("Only Family Admins can invite new members.");
    }

    final cleanUsername = targetUsername.trim();
    if (cleanUsername.isEmpty) throw Exception("Please enter a username.");

    final myUsername = await getCurrentUsername();
    if (cleanUsername.toLowerCase() == myUsername.toLowerCase()) {
      throw Exception("You cannot invite yourself.");
    }

    final userSnap = await _firestore.collection('usernames').doc(cleanUsername).get();
    if (!userSnap.exists) {
      throw Exception("User '@$cleanUsername' not found.");
    }

    final targetUid = (userSnap.data()?['uid'] ?? '').toString();
    if (targetUid.isEmpty) throw Exception("User '@$cleanUsername' has no valid account.");

    final collabs = List<String>.from(familyData['collaboratorUids'] ?? []);
    if (collabs.contains(targetUid)) {
      throw Exception("User '@$cleanUsername' is already a member of your family.");
    }

    final pending = List<Map<String, dynamic>>.from(familyData['pendingInvites'] ?? []);
    if (pending.any((p) => p['uid'] == targetUid)) {
      throw Exception("An invitation has already been sent to @$cleanUsername.");
    }

    final targetUserDoc = await _firestore.collection('users').doc(targetUid).get();
    final targetFamilyId = (targetUserDoc.data()?['familyId'] ?? '').toString();
    if (targetFamilyId.isNotEmpty) {
      throw Exception("User '@$cleanUsername' is already a member of another family.");
    }

    pending.add({
      'uid': targetUid,
      'username': cleanUsername,
      'senderUid': uid,
      'senderUsername': myUsername,
    });

    await _firestore.collection('families').doc(familyId).update({'pendingInvites': pending});
  }

  /// Respond to a family invitation (Accept or Reject)
  Future<void> respondToFamilyInvite(String familyId, bool accept) async {
    final uid = _currentUserId;
    if (uid == null) throw Exception("User not authenticated.");

    final familySnap = await _firestore.collection('families').doc(familyId).get();
    if (!familySnap.exists) throw Exception("Family invitation no longer exists.");

    final familyData = familySnap.data()!;
    final pending = List<Map<String, dynamic>>.from(familyData['pendingInvites'] ?? []);

    if (accept) {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      final existingFamilyId = (userDoc.data()?['familyId'] ?? '').toString();
      if (existingFamilyId.isNotEmpty) {
        throw Exception("You are already a member of a family. You cannot join multiple families.");
      }

      final collabs = List<String>.from(familyData['collaboratorUids'] ?? []);
      if (!collabs.contains(uid)) collabs.add(uid);

      pending.removeWhere((p) => p['uid'] == uid);

      await _firestore.collection('families').doc(familyId).update({
        'collaboratorUids': collabs,
        'pendingInvites': pending,
      });

      await _firestore.collection('users').doc(uid).set({'familyId': familyId}, SetOptions(merge: true));
    } else {
      pending.removeWhere((p) => p['uid'] == uid);
      await _firestore.collection('families').doc(familyId).update({
        'pendingInvites': pending,
      });
    }
  }

  /// Add a virtual profile to family
  Future<void> addVirtualProfile(String familyId, String profileName) async {
    final uid = _currentUserId;
    if (uid == null) throw Exception("User not authenticated.");

    final familySnap = await _firestore.collection('families').doc(familyId).get();
    if (!familySnap.exists) throw Exception("Family not found.");

    final profiles = List<Map<String, dynamic>>.from(familySnap.data()!['virtualProfiles'] ?? []);
    final id = 'vp_${DateTime.now().millisecondsSinceEpoch}';

    profiles.add({
      'id': id,
      'name': profileName.trim(),
      'createdBy': uid,
    });

    await _firestore.collection('families').doc(familyId).update({'virtualProfiles': profiles});
  }

  /// Delete a virtual profile from family
  Future<void> deleteVirtualProfile(String familyId, String profileId) async {
    final uid = _currentUserId;
    if (uid == null) throw Exception("User not authenticated.");

    final familySnap = await _firestore.collection('families').doc(familyId).get();
    if (!familySnap.exists) return;

    final profiles = List<Map<String, dynamic>>.from(familySnap.data()!['virtualProfiles'] ?? []);
    profiles.removeWhere((p) => p['id'] == profileId);

    await _firestore.collection('families').doc(familyId).update({'virtualProfiles': profiles});
  }

  /// Remove a collaborator from family (Admin only)
  Future<void> removeCollaboratorFromFamily(String familyId, String targetUid) async {
    final uid = _currentUserId;
    if (uid == null) throw Exception("User not authenticated.");

    final familySnap = await _firestore.collection('families').doc(familyId).get();
    if (!familySnap.exists) throw Exception("Family not found.");

    final adminUids = List<String>.from(familySnap.data()!['adminUids'] ?? []);
    if (!adminUids.contains(uid)) throw Exception("Only Family Admins can remove members.");

    final collabs = List<String>.from(familySnap.data()!['collaboratorUids'] ?? []);
    collabs.remove(targetUid);
    adminUids.remove(targetUid);

    await _firestore.collection('families').doc(familyId).update({
      'collaboratorUids': collabs,
      'adminUids': adminUids,
    });

    await _firestore.collection('users').doc(targetUid).update({'familyId': FieldValue.delete()});
  }

  /// Promote collaborator to Admin (Admin only)
  Future<void> promoteToAdmin(String familyId, String targetUid) async {
    final uid = _currentUserId;
    if (uid == null) throw Exception("User not authenticated.");

    final familySnap = await _firestore.collection('families').doc(familyId).get();
    if (!familySnap.exists) throw Exception("Family not found.");

    final adminUids = List<String>.from(familySnap.data()!['adminUids'] ?? []);
    if (!adminUids.contains(uid)) throw Exception("Only Family Admins can promote members.");

    if (!adminUids.contains(targetUid)) {
      adminUids.add(targetUid);
      await _firestore.collection('families').doc(familyId).update({'adminUids': adminUids});
    }
  }

  /// Delete family (Admin only)
  Future<void> deleteFamily(String familyId) async {
    final uid = _currentUserId;
    if (uid == null) throw Exception("User not authenticated.");

    final familySnap = await _firestore.collection('families').doc(familyId).get();
    if (!familySnap.exists) return;

    final familyData = familySnap.data()!;
    final adminUids = List<String>.from(familyData['adminUids'] ?? []);
    if (!adminUids.contains(uid)) throw Exception("Only Family Admins can delete the family.");

    final collabs = List<String>.from(familyData['collaboratorUids'] ?? []);

    for (var cUid in collabs) {
      await _firestore.collection('users').doc(cUid).update({'familyId': FieldValue.delete()});
    }

    await _firestore.collection('families').doc(familyId).delete();
  }

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
      debugPrint("VaultService: Error fetching username: $e");
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
          debugPrint("VaultService: Error listening to sent collabs: $e");
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
          debugPrint("VaultService: Error listening to received collabs: $e");
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

  /// Stream of raw (encrypted) secure documents for current user and all approved collaborators
  Stream<List<SecureDocument>> getSecureDocuments() {
    final uid = _currentUserId;
    if (uid == null) return Stream.value([]);

    late StreamController<List<SecureDocument>> controller;
    StreamSubscription? collabSub;
    final Map<String, StreamSubscription> docSubs = {};
    final Map<String, List<SecureDocument>> docsPerUser = {};

    void updateCombinedDocs() {
      if (controller.isClosed) return;
      final List<SecureDocument> allDocs = [];
      for (var list in docsPerUser.values) {
        allDocs.addAll(list);
      }
      allDocs.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
      controller.add(allDocs);
    }

    controller = StreamController<List<SecureDocument>>.broadcast(
      onListen: () {
        collabSub = getVaultCollaborators().listen((collaborators) {
          final Set<String> activeUids = collaborators.map((c) => c.uid).toSet();
          activeUids.add(uid);

          // Cancel subscriptions for UIDs no longer active
          final existingUids = docSubs.keys.toList();
          for (var userUid in existingUids) {
            if (!activeUids.contains(userUid)) {
              docSubs[userUid]?.cancel();
              docSubs.remove(userUid);
              docsPerUser.remove(userUid);
            }
          }

          // Subscribe to snapshot stream for any new active UIDs
          for (var userUid in activeUids) {
            if (!docSubs.containsKey(userUid)) {
              docSubs[userUid] = _firestore
                  .collection('users')
                  .doc(userUid)
                  .collection('secure_documents')
                  .snapshots()
                  .listen((snap) {
                docsPerUser[userUid] = snap.docs
                    .map((d) => SecureDocument.fromMap(d.data()))
                    .where((d) {
                  // If document belongs to another user and is marked private, exclude it!
                  if (userUid != uid && d.isPrivate) return false;
                  return true;
                }).toList();
                updateCombinedDocs();
              }, onError: (e) {
                debugPrint("VaultService: Error listening to docs for user $userUid: $e");
              });
            }
          }

          updateCombinedDocs();
        }, onError: (e) {
          debugPrint("VaultService: Error listening to collaborators: $e");
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

  /// Stream of unique category names from existing documents across user's vault
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

  /// Decrypt a single document into memory safely
  Future<DecryptedDocument?> decryptDocument(SecureDocument doc) async {
    final encryptionService = EncryptionService();
    try {
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
    } catch (e) {
      debugPrint("VaultService: Error decrypting document ${doc.id}: $e");
      return null;
    }
  }

  /// Save or update a document locally encrypted
  Future<void> saveDocument({
    String? id,
    required String memberId, // Owner UID or Virtual Family Member ID
    required String ownerName,
    required String category,
    required String title,
    required Map<String, String> fields,
    required List<Uint8List> rawImagesToUpload,
    required List<String> newAttachmentsNames,
    required List<String> existingAttachmentPaths,
    String? targetOwnerUid,
    bool isPrivate = false,
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

    String effectiveTargetUid = uid;
    if (targetOwnerUid != null && targetOwnerUid.isNotEmpty) {
      effectiveTargetUid = targetOwnerUid;
    }

    final docId = id ?? _firestore.collection('users').doc(effectiveTargetUid).collection('secure_documents').doc().id;

    final List<String> uploadedPaths = List.from(existingAttachmentPaths);

    for (int i = 0; i < rawImagesToUpload.length; i++) {
      final rawBytes = rawImagesToUpload[i];
      final encryptedBytes = await encryptionService.encryptBytes(rawBytes);

      final originalName = newAttachmentsNames[i];
      final ext = originalName.contains('.') ? originalName.split('.').last : 'bin';
      
      final safeOwner = ownerName.replaceAll(RegExp(r'[^\w\-_]'), '_');
      final safeTitle = title.replaceAll(RegExp(r'[^\w\-_]'), '_');
      
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storagePath = 'users/$uid/vault_attachments/$docId/${safeOwner}_-_${safeTitle}_${timestamp}_$i.$ext';
      
      final ref = _storage.ref().child(storagePath);
      await ref.putData(
        encryptedBytes,
        SettableMetadata(contentType: 'application/octet-stream'),
      );
      
      uploadedPaths.add(storagePath);
    }

    final doc = SecureDocument(
      id: docId,
      memberId: memberId.isNotEmpty ? memberId : uid,
      category: category,
      encryptedTitle: encryptedTitle,
      encryptedFields: encryptedFields,
      encryptedAttachmentPaths: uploadedPaths,
      lastUpdated: DateTime.now(),
      isPrivate: isPrivate,
    );

    await _firestore
        .collection('users')
        .doc(effectiveTargetUid)
        .collection('secure_documents')
        .doc(docId)
        .set(doc.toMap());
  }

  /// Delete a secure document and all its associated encrypted attachments from Storage
  Future<void> deleteDocument(SecureDocument doc) async {
    final uid = _currentUserId;
    if (uid == null) throw Exception("User not authenticated.");

    String effectiveTargetUid = uid;
    if (doc.memberId.isNotEmpty && doc.memberId != uid) {
      try {
        final collaborators = await getVaultCollaborators().first;
        if (collaborators.any((c) => c.uid == doc.memberId && !c.isSelf)) {
          effectiveTargetUid = doc.memberId;
        }
      } catch (_) {}
    }

    for (var path in doc.encryptedAttachmentPaths) {
      try {
        await _storage.ref().child(path).delete();
      } catch (e) {
        debugPrint("VaultService: Error deleting attachment $path: $e");
      }
    }

    await _firestore
        .collection('users')
        .doc(effectiveTargetUid)
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
      debugPrint("VaultService: Error downloading/decrypting attachment: $e");
      return null;
    }
  }

  // ==========================================
  // FAMILY MEMBER PROFILES METHODS
  // ==========================================

  Stream<List<FamilyMember>> getFamilyMembers() {
    final uid = _currentUserId;
    if (uid == null) return Stream.value([]);

    return _firestore
        .collection('users')
        .doc(uid)
        .collection('family_members')
        .snapshots()
        .map((snap) => snap.docs.map((d) => FamilyMember.fromMap(d.data(), d.id)).toList());
  }

  /// Stream of unified member profiles (Myself, Virtual Family Members, and App Collaborators)
  Stream<List<VaultMemberProfile>> getUnifiedMemberProfiles() {
    final uid = _currentUserId;
    if (uid == null) return Stream.value([]);

    late StreamController<List<VaultMemberProfile>> controller;
    StreamSubscription? collabSub;
    StreamSubscription? familySub;
    StreamSubscription? vaultFamilySub;

    List<VaultCollaborator> collabs = [];
    List<FamilyMember> familyMembers = [];
    VaultFamily? activeVaultFamily;

    void emitProfiles() {
      final List<VaultMemberProfile> profiles = [];

      // 1. Add Myself & Collaborators from collabs stream
      for (var c in collabs) {
        if (c.isSelf) {
          profiles.add(VaultMemberProfile(
            id: c.uid,
            name: 'Myself (@${c.username})',
            rawName: '@${c.username}',
            subtext: 'Account Owner',
            avatarColorValue: c.avatarColorValue,
            isSelf: true,
          ));
        }
      }

      // 2. Add Family Virtual Profiles (from VaultFamily)
      if (activeVaultFamily != null) {
        for (var vp in activeVaultFamily!.virtualProfiles) {
          profiles.add(VaultMemberProfile(
            id: vp.id,
            name: vp.name,
            rawName: vp.name,
            subtext: 'Family Virtual Profile',
            avatarColorValue: VaultCollaborator.generateColorForUser(vp.name),
            isVirtual: true,
          ));
        }
      }

      // 3. Add Legacy Virtual Family Members
      for (var fm in familyMembers) {
        profiles.add(VaultMemberProfile(
          id: fm.id,
          name: '${fm.name} (${fm.relationship})',
          rawName: fm.name,
          subtext: 'Virtual • ${fm.relationship}',
          avatarColorValue: fm.avatarColorValue,
          isVirtual: true,
        ));
      }

      // 4. Add Real App Collaborators
      for (var c in collabs) {
        if (!c.isSelf) {
          profiles.add(VaultMemberProfile(
            id: c.uid,
            name: '@${c.username}',
            rawName: '@${c.username}',
            subtext: 'App Collaborator',
            avatarColorValue: c.avatarColorValue,
            isCollaborator: true,
          ));
        }
      }

      if (!controller.isClosed) {
        controller.add(profiles);
      }
    }

    controller = StreamController<List<VaultMemberProfile>>.broadcast(
      onListen: () {
        collabSub = getVaultCollaborators().listen((list) {
          collabs = list;
          emitProfiles();
        });

        familySub = getFamilyMembers().listen((list) {
          familyMembers = list;
          emitProfiles();
        });

        vaultFamilySub = getFamilyStream().listen((fam) {
          activeVaultFamily = fam;
          emitProfiles();
        });
      },
      onCancel: () {
        collabSub?.cancel();
        familySub?.cancel();
        vaultFamilySub?.cancel();
      },
    );

    return controller.stream;
  }

  Future<void> addFamilyMember(String name, String relationship, int avatarColorValue) async {
    final uid = _currentUserId;
    if (uid == null) throw Exception("User not authenticated.");

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('family_members')
        .add({
      'name': name,
      'relationship': relationship,
      'avatarColorValue': avatarColorValue,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

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

  Future<void> deleteFamilyMember(String id) async {
    final uid = _currentUserId;
    if (uid == null) throw Exception("User not authenticated.");

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('family_members')
        .doc(id)
        .delete();
  }
}
