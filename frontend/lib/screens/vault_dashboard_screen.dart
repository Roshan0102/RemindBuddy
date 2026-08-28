import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/encryption_service.dart';
import '../models/secure_document.dart';
import '../models/vault_collaborator.dart';
import '../models/vault_member_profile.dart';
import '../models/vault_family.dart';
import '../services/vault_service.dart';
import 'vault_collaboration_screen.dart';
import 'family_management_screen.dart';
import 'add_document_screen.dart';
import 'document_detail_screen.dart';

class VaultDashboardScreen extends StatefulWidget {
  const VaultDashboardScreen({super.key});

  @override
  State<VaultDashboardScreen> createState() => _VaultDashboardScreenState();
}

class _VaultDashboardScreenState extends State<VaultDashboardScreen> {
  final VaultService _vaultService = VaultService();
  StreamSubscription? _collaboratorSubscription;
  StreamSubscription? _profilesSubscription;
  final TextEditingController _searchController = TextEditingController();
  List<SecureDocument>? _previousRawDocs;
  Future<List<DecryptedDocument>>? _decryptionFuture;

  String _searchQuery = '';
  String? _selectedMemberId; // null means "All Members"
  String _selectedCategory = 'All'; // "All" or a specific category
  String _vaultViewMode = 'family'; // 'family' (Family Shared), 'private' (My Private), 'all' (All)

  Map<String, VaultCollaborator> _collaboratorsMap = {};
  Map<String, VaultMemberProfile> _profilesMap = {};

  @override
  void initState() {
    super.initState();
    _loadSavedViewMode();
    _loadCollaborators();
    _loadProfiles();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase().trim();
      });
    });
  }

  Future<void> _loadSavedViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString('vault_view_mode') ?? 'family';
    if (mounted) {
      setState(() {
        _vaultViewMode = savedMode;
      });
    }
  }

  Future<void> _setSavedViewMode(String mode) async {
    setState(() {
      _vaultViewMode = mode;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vault_view_mode', mode);
  }

  @override
  void dispose() {
    _collaboratorSubscription?.cancel();
    _profilesSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _loadCollaborators() {
    _collaboratorSubscription?.cancel();
    _collaboratorSubscription = _vaultService.getVaultCollaborators().listen((list) {
      if (mounted) {
        setState(() {
          _collaboratorsMap = {for (var c in list) c.uid: c};
        });
      }
    });
  }

  void _loadProfiles() {
    _profilesSubscription?.cancel();
    _profilesSubscription = _vaultService.getUnifiedMemberProfiles().listen((list) {
      if (mounted) {
        setState(() {
          _profilesMap = {for (var p in list) p.id: p};
        });
      }
    });
  }

  void _copyToClipboard(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied $label to clipboard!'),
        backgroundColor: Colors.blueAccent,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _shareField(String label, String value) {
    // ignore: deprecated_member_use
    Share.share('$label: $value', subject: 'Document Details');
  }

  void _shareAllFilteredDocuments(List<DecryptedDocument> docs) {
    if (docs.isEmpty) return;

    final StringBuffer buffer = StringBuffer();
    buffer.writeln('🔒 Shared Secure Vault Documents (${docs.length}):\n');

    for (int i = 0; i < docs.length; i++) {
      final d = docs[i];
      final profileName = _profilesMap[d.original.memberId]?.name ?? 'Vault Profile';
      buffer.writeln('${i + 1}. [${profileName.toUpperCase()}] - ${d.title}');
      buffer.writeln('   Category: ${d.original.category}');

      for (var entry in d.fields.entries) {
        if (entry.value.trim().isNotEmpty) {
          buffer.writeln('   • ${entry.key}: ${entry.value}');
        }
      }
      buffer.writeln('');
    }

    // ignore: deprecated_member_use
    Share.share(buffer.toString(), subject: 'Shared Vault Documents (${docs.length})');
  }

  void _showChangePinDialog() {
    final currentPinController = TextEditingController();
    final newPinController = TextEditingController();
    final confirmPinController = TextEditingController();
    String errorMsg = '';
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.password_rounded, color: Colors.blueAccent),
                  SizedBox(width: 8),
                  Text('Change Vault PIN'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: currentPinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'Current PIN',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: newPinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'New 4-Digit PIN',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: confirmPinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'Confirm New PIN',
                      counterText: '',
                    ),
                  ),
                  if (errorMsg.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorMsg,
                      style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final curr = currentPinController.text.trim();
                          final nPin = newPinController.text.trim();
                          final cPin = confirmPinController.text.trim();

                          if (curr.length < 4 || nPin.length < 4) {
                            setDialogState(() => errorMsg = 'PINs must be at least 4 digits.');
                            return;
                          }

                          if (nPin != cPin) {
                            setDialogState(() => errorMsg = 'New PIN and Confirm PIN do not match.');
                            return;
                          }

                          setDialogState(() {
                            isSaving = true;
                            errorMsg = '';
                          });

                          try {
                            final uid = FirebaseAuth.instance.currentUser?.uid;
                            if (uid == null) throw Exception("User not authenticated.");

                            final doc = await FirebaseFirestore.instance
                                .collection('users')
                                .doc(uid)
                                .collection('vault_config')
                                .doc('pin')
                                .get();

                            String? salt;
                            String? verifier;

                            if (doc.exists && doc.data() != null) {
                              salt = doc.data()!['salt'];
                              verifier = doc.data()!['verifier'];
                            }

                            final encryptionService = EncryptionService();
                            if (salt == null || verifier == null || !encryptionService.verifyDecryption(verifier, curr, salt)) {
                              setDialogState(() {
                                isSaving = false;
                                errorMsg = 'Current PIN is incorrect.';
                              });
                              return;
                            }

                            final newSalt = encryptionService.generateSalt();
                            encryptionService.setKeyFromPIN(nPin, newSalt);
                            final newVerifier = encryptionService.encryptVerifier();

                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(uid)
                                .collection('vault_config')
                                .doc('pin')
                                .set({
                              'salt': newSalt,
                              'verifier': newVerifier,
                              'updatedAt': FieldValue.serverTimestamp(),
                            });

                            if (mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('🔑 Vault PIN changed successfully!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() {
                              isSaving = false;
                              errorMsg = 'Error changing PIN: $e';
                            });
                          }
                        },
                  child: isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Change PIN'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showCreateFamilyDialog(BuildContext parentContext) {
    final nameCtrl = TextEditingController();
    showDialog(
      context: parentContext,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Create a Family', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Family Name (e.g. Roshan\'s Family)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              try {
                await _vaultService.createFamily(nameCtrl.text.trim());
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('$e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showAddVirtualProfileDialog(BuildContext parentContext, String familyId) {
    final profileCtrl = TextEditingController();
    showDialog(
      context: parentContext,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add Virtual Profile', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: profileCtrl,
          decoration: const InputDecoration(
            labelText: 'Profile Name (e.g. Dad, Mom, Spouse, Son)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (profileCtrl.text.trim().isEmpty) return;
              await _vaultService.addVirtualProfile(familyId, profileCtrl.text.trim());
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showInviteMemberDialog(BuildContext parentContext, String familyId) {
    final userCtrl = TextEditingController();
    showDialog(
      context: parentContext,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Invite Family Member', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: userCtrl,
          decoration: const InputDecoration(
            labelText: 'Enter App Username (e.g. john_doe)',
            prefixText: '@',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (userCtrl.text.trim().isEmpty) return;
              try {
                await _vaultService.inviteToFamily(familyId, userCtrl.text.trim());
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Invitation sent to @${userCtrl.text.trim()}!'), backgroundColor: Colors.green),
                  );
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('$e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Send Invite'),
          ),
        ],
      ),
    );
  }

  void _showFamilyVaultDialog(BuildContext parentContext) {
    showDialog(
      context: parentContext,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final user = FirebaseAuth.instance.currentUser;
          if (user == null) return const SizedBox.shrink();

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: StreamBuilder<VaultFamily?>(
              stream: _vaultService.getFamilyStream(),
              builder: (context, famSnapshot) {
                if (famSnapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final family = famSnapshot.data;

                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _vaultService.getPendingFamilyInvitesStream(),
                  builder: (context, invitesSnapshot) {
                    final pendingInvites = invitesSnapshot.data ?? [];
                    final isAdmin = family != null && family.adminUids.contains(user.uid);

                    return Container(
                      constraints: const BoxConstraints(maxWidth: 500, maxHeight: 650),
                      padding: const EdgeInsets.all(20),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header Title
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.family_restroom_rounded, color: Colors.blueAccent, size: 28),
                                    const SizedBox(width: 10),
                                    Text(
                                      family != null ? family.name : 'Family Vault',
                                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () => Navigator.pop(dialogCtx),
                                ),
                              ],
                            ),
                            const Divider(height: 24),

                            // PENDING INVITATIONS (IF ANY)
                            if (pendingInvites.isNotEmpty && family == null) ...[
                              const Text('Pending Invitations', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueAccent)),
                              const SizedBox(height: 8),
                              ...pendingInvites.map((invite) {
                                return Card(
                                  color: Colors.blue.shade50,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  child: ListTile(
                                    title: Text('Invite to join "${invite['familyName']}"', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    subtitle: Text('Sent by @${invite['senderUsername']}', style: const TextStyle(fontSize: 12)),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                          onPressed: () async {
                                            try {
                                              await _vaultService.respondToFamilyInvite(invite['familyId'], true);
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(content: Text('Joined family successfully!'), backgroundColor: Colors.green),
                                                );
                                              }
                                            } catch (e) {
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(content: Text('$e'), backgroundColor: Colors.red),
                                                );
                                              }
                                            }
                                          },
                                          child: const Text('Accept', style: TextStyle(fontSize: 12)),
                                        ),
                                        const SizedBox(width: 6),
                                        TextButton(
                                          onPressed: () async {
                                            await _vaultService.respondToFamilyInvite(invite['familyId'], false);
                                          },
                                          child: const Text('Decline', style: TextStyle(color: Colors.red, fontSize: 12)),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                              const SizedBox(height: 16),
                            ],

                            // STATE A: NO FAMILY CREATED YET
                            if (family == null) ...[
                              Center(
                                child: Column(
                                  children: [
                                    const SizedBox(height: 12),
                                    Icon(Icons.diversity_3_rounded, size: 64, color: Colors.grey.shade400),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'No Family Created Yet',
                                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'Create a family group to share documents across virtual profiles and invite app members.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.grey, fontSize: 13),
                                    ),
                                    const SizedBox(height: 20),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blueAccent,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      icon: const Icon(Icons.add_rounded),
                                      label: const Text('Create a Family', style: TextStyle(fontWeight: FontWeight.bold)),
                                      onPressed: () {
                                        _showCreateFamilyDialog(context);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ] else ...[
                              // STATE B: FAMILY ACTIVE
                              // Admin Badge Card
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isAdmin ? Colors.amber.shade50 : Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: isAdmin ? Colors.amber.shade300 : Colors.blue.shade300),
                                ),
                                child: Row(
                                  children: [
                                    Icon(isAdmin ? Icons.workspace_premium_rounded : Icons.group_rounded, color: isAdmin ? Colors.amber.shade900 : Colors.blue.shade900),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        isAdmin ? 'You are the Admin of ${family.name}' : 'Member of ${family.name}',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isAdmin ? Colors.amber.shade900 : Colors.blue.shade900),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              // VIRTUAL PROFILES SECTION
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Virtual Profiles', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  TextButton.icon(
                                    icon: const Icon(Icons.add, size: 18),
                                    label: const Text('Add Profile', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    onPressed: () {
                                      _showAddVirtualProfileDialog(context, family.id);
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ...family.virtualProfiles.map((vp) {
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  child: ListTile(
                                    dense: true,
                                    leading: CircleAvatar(
                                      radius: 14,
                                      backgroundColor: Color(VaultCollaborator.generateColorForUser(vp.name)),
                                      child: Text(vp.name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                    ),
                                    title: Text(vp.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                    trailing: (isAdmin && vp.id != 'vp_self')
                                        ? IconButton(
                                            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                                            onPressed: () async {
                                              await _vaultService.deleteVirtualProfile(family.id, vp.id);
                                            },
                                          )
                                        : null,
                                  ),
                                );
                              }).toList(),
                              const SizedBox(height: 16),

                              // COLLABORATORS SECTION
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Family App Members', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  if (isAdmin)
                                    TextButton.icon(
                                      icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                                      label: const Text('Invite Member', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                      onPressed: () {
                                        _showInviteMemberDialog(context, family.id);
                                      },
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ...family.collaboratorUids.map((cUid) {
                                final isCAdmin = family.adminUids.contains(cUid);
                                final isMe = cUid == user.uid;

                                return FutureBuilder<DocumentSnapshot>(
                                  future: FirebaseFirestore.instance.collection('users').doc(cUid).get(),
                                  builder: (context, uSnap) {
                                    String displayName = isMe ? 'You' : cUid;
                                    if (uSnap.hasData && uSnap.data?.data() != null) {
                                      final d = uSnap.data!.data() as Map<String, dynamic>;
                                      displayName = (d['displayName'] ?? d['email'] ?? cUid).toString();
                                    }

                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      child: ListTile(
                                        dense: true,
                                        leading: CircleAvatar(
                                          radius: 14,
                                          backgroundColor: isCAdmin ? Colors.amber : Colors.blueAccent,
                                          child: Icon(isCAdmin ? Icons.star : Icons.person, color: Colors.white, size: 14),
                                        ),
                                        title: Text(isMe ? '$displayName (You)' : displayName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                        subtitle: Text(isCAdmin ? 'Admin' : 'Member', style: const TextStyle(fontSize: 11)),
                                        trailing: (isAdmin && !isMe)
                                            ? PopupMenuButton<String>(
                                                onSelected: (val) async {
                                                  if (val == 'promote') {
                                                    await _vaultService.promoteToAdmin(family.id, cUid);
                                                  } else if (val == 'remove') {
                                                    await _vaultService.removeCollaboratorFromFamily(family.id, cUid);
                                                  }
                                                },
                                                itemBuilder: (ctx) => [
                                                  if (!isCAdmin)
                                                    const PopupMenuItem(value: 'promote', child: Text('Promote to Admin')),
                                                  const PopupMenuItem(value: 'remove', child: Text('Remove from Family', style: TextStyle(color: Colors.red))),
                                                ],
                                              )
                                            : null,
                                      ),
                                    );
                                  },
                                );
                              }).toList(),

                              // PENDING SENT INVITES LIST
                              if (family.pendingInvites.isNotEmpty && isAdmin) ...[
                                const SizedBox(height: 12),
                                Text('Pending Sent Invites', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey.shade600)),
                                const SizedBox(height: 4),
                                ...family.pendingInvites.map((p) {
                                  return Card(
                                    color: Colors.grey.shade100,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('@${p['username']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                          const Text('Pending...', style: TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ],

                              const SizedBox(height: 20),
                              const Divider(),

                              // DELETE / LEAVE FAMILY ACTIONS
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                                  icon: Icon(isAdmin ? Icons.delete_forever_rounded : Icons.exit_to_app_rounded),
                                  label: Text(isAdmin ? 'Delete Family' : 'Leave Family', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        title: Text(isAdmin ? 'Delete Family?' : 'Leave Family?'),
                                        content: Text(isAdmin
                                            ? 'This will delete the family group for all members.'
                                            : 'You will no longer have access to family shared documents.'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                                          TextButton(
                                            onPressed: () => Navigator.pop(c, true),
                                            style: TextButton.styleFrom(foregroundColor: Colors.red),
                                            child: const Text('Confirm'),
                                          ),
                                        ],
                                      ),
                                    );

                                    if (confirm == true) {
                                      if (isAdmin) {
                                        await _vaultService.deleteFamily(family.id);
                                      } else {
                                        await _vaultService.removeCollaboratorFromFamily(family.id, user.uid);
                                      }
                                      if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🔒 Secure Document Vault'),
        actions: [
          IconButton(
            icon: const Icon(Icons.family_restroom_rounded),
            onPressed: () => _showFamilyVaultDialog(context),
            tooltip: 'Family Vault & Profiles',
          ),
          IconButton(
            icon: const Icon(Icons.password_rounded),
            onPressed: _showChangePinDialog,
            tooltip: 'Change Vault PIN',
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Search Bar (ALWAYS visible, never loses focus/keyboard!)
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search documents, Aadhar, accounts...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          FocusScope.of(context).unfocus();
                        },
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
          ),

          // 2. Async Filter & List Area
          Expanded(
            child: StreamBuilder<List<SecureDocument>>(
              stream: _vaultService.getSecureDocuments(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final rawDocs = snapshot.data ?? [];
                if (rawDocs.isEmpty) {
                  return _buildEmptyState();
                }

                if (_decryptionFuture == null || _previousRawDocs == null || !_areRawDocsEqual(_previousRawDocs!, rawDocs)) {
                  _previousRawDocs = rawDocs;
                  _decryptionFuture = _decryptAllDocuments(rawDocs);
                }

                return FutureBuilder<List<DecryptedDocument>>(
                  future: _decryptionFuture,
                  builder: (context, decryptSnapshot) {
                    if (decryptSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 12),
                            Text('Decrypting vault securely in memory...'),
                          ],
                        ),
                      );
                    }

                    final decDocs = decryptSnapshot.data ?? [];

                    // Compute categories list purely dynamically based on user and collaborator documents!
                    final Set<String> uniqueCategories = {'All'};
                    for (var doc in decDocs) {
                      if (doc.original.category.trim().isNotEmpty) {
                        uniqueCategories.add(doc.original.category.trim());
                      }
                    }
                    final dynamicCategories = uniqueCategories.toList();

                    // If the selected category is no longer in the list of dynamic categories, reset to 'All'
                    if (!dynamicCategories.contains(_selectedCategory)) {
                      _selectedCategory = 'All';
                    }

                    // Apply filters (Vault View Mode, Selected Member, Category, Search Query)
                    final filteredDocs = decDocs.where((doc) {
                      // Filter by Privacy / Vault View Mode
                      if (_vaultViewMode == 'private') {
                        if (!doc.original.isPrivate) return false;
                      } else if (_vaultViewMode == 'family') {
                        if (doc.original.isPrivate) return false;
                      }

                      // Filter by Member
                      if (_selectedMemberId != null && doc.original.memberId != _selectedMemberId) {
                        return false;
                      }

                      // Filter by Category
                      if (_selectedCategory != 'All' && doc.original.category != _selectedCategory) {
                        return false;
                      }

                      // Filter by Search query
                      if (_searchQuery.isNotEmpty) {
                        final titleMatch = doc.title.toLowerCase().contains(_searchQuery);
                        final fieldsKeyMatch = doc.fields.keys.any((k) => k.toLowerCase().contains(_searchQuery));
                        final fieldsValueMatch = doc.fields.values.any((v) => v.toLowerCase().contains(_searchQuery));
                        return titleMatch || fieldsKeyMatch || fieldsValueMatch;
                      }

                      return true;
                    }).toList();

                    // Sort documents alphabetically by title (A-Z)
                    filteredDocs.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

                    return Column(
                      children: [
                        // Filters row
                        Padding(
                          padding: const EdgeInsets.only(left: 12.0, right: 12.0, bottom: 8.0),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                // 1. Vault View Mode Dropdown (Cached in SharedPreferences)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.indigo.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.indigo.shade200),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _vaultViewMode,
                                      icon: const Icon(Icons.tune_rounded, color: Colors.indigo),
                                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo.shade900, fontSize: 13),
                                      items: const [
                                        DropdownMenuItem<String>(
                                          value: 'family',
                                          child: Row(
                                            children: [
                                              Icon(Icons.people_alt_outlined, size: 18, color: Colors.indigo),
                                              SizedBox(width: 6),
                                              Text('Family Shared'),
                                            ],
                                          ),
                                        ),
                                        DropdownMenuItem<String>(
                                          value: 'private',
                                          child: Row(
                                            children: [
                                              Icon(Icons.lock_outline, size: 18, color: Colors.red),
                                              SizedBox(width: 6),
                                              Text('My Private'),
                                            ],
                                          ),
                                        ),
                                        DropdownMenuItem<String>(
                                          value: 'all',
                                          child: Row(
                                            children: [
                                              Icon(Icons.auto_awesome, size: 18, color: Colors.purple),
                                              SizedBox(width: 6),
                                              Text('All Documents'),
                                            ],
                                          ),
                                        ),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) {
                                          _setSavedViewMode(val);
                                        }
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // Share All Button
                                if (filteredDocs.isNotEmpty) ...[
                                  ElevatedButton.icon(
                                    onPressed: () => _shareAllFilteredDocuments(filteredDocs),
                                    icon: const Icon(Icons.share_rounded, size: 16),
                                    label: Text('Share All (${filteredDocs.length})'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.indigo.shade700,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],

                                // Member Filter (Unified Profiles: Myself, Virtual Profiles, Collaborators)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _profilesMap.containsKey(_selectedMemberId) ? _selectedMemberId : null,
                                      hint: const Text('All Vault Profiles'),
                                      icon: const Icon(Icons.arrow_drop_down, color: Colors.indigo),
                                      items: [
                                        const DropdownMenuItem<String>(
                                          value: null,
                                          child: Text('All Vault Members & Profiles'),
                                        ),
                                        ..._profilesMap.values.map((p) {
                                          return DropdownMenuItem<String>(
                                            value: p.id,
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                CircleAvatar(
                                                  radius: 10,
                                                  backgroundColor: Color(p.avatarColorValue),
                                                  child: Text(
                                                    p.rawName.isNotEmpty ? p.rawName[0].toUpperCase() : '?',
                                                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(p.name),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                      ],
                                      onChanged: (val) {
                                        setState(() {
                                          _selectedMemberId = val;
                                        });
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Category Filter Dropdown
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _selectedCategory,
                                      icon: const Icon(Icons.category_outlined, color: Colors.indigo),
                                      items: dynamicCategories.map((c) {
                                        return DropdownMenuItem<String>(
                                          value: c,
                                          child: Text(c == 'All' ? 'All Categories' : c),
                                        );
                                      }).toList(),
                                      onChanged: (val) {
                                        setState(() {
                                          _selectedCategory = val ?? 'All';
                                        });
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // List of documents
                        Expanded(
                          child: filteredDocs.isEmpty
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(24.0),
                                    child: Text(
                                      'No documents match your search.',
                                      style: TextStyle(color: Colors.grey, fontSize: 16),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  itemCount: filteredDocs.length,
                                  itemBuilder: (context, index) {
                                    final decDoc = filteredDocs[index];
                                    final profile = _profilesMap[decDoc.original.memberId];
                                    return _buildDocumentCard(decDoc, profile);
                                  },
                                ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddDocumentScreen()),
          );
        },
        icon: const Icon(Icons.add_moderator),
        label: const Text('Add Document'),
      ),
    );
  }

  Widget _buildDocumentCard(DecryptedDocument decDoc, VaultMemberProfile? profile) {
    final ownerName = profile != null ? profile.name : 'Myself';
    final avatarColor = profile?.avatarColorValue ?? 0xFF3F51B5;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DocumentDetailScreen(
                document: decDoc.original,
                decryptedDocument: decDoc,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Row: Owner avatar, Document title, and Category
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Color(avatarColor).withAlpha(38),
                    child: Text(
                      profile != null && profile.rawName.isNotEmpty
                          ? profile.rawName.substring(0, 1).toUpperCase()
                          : 'M',
                      style: TextStyle(
                        color: Color(avatarColor),
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          decDoc.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              'Owner: ',
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                            ),
                            Text(
                              ownerName,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(avatarColor),
                              ),
                            ),
                            Text(
                              '  |  ${decDoc.original.category}',
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    onPressed: () => _deleteDocument(decDoc.original),
                    tooltip: 'Delete Document',
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
              const Divider(height: 24, thickness: 1),

              // Credentials Field List
              if (decDoc.fields.isNotEmpty) ...[
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: decDoc.fields.length,
                  itemBuilder: (context, fIdx) {
                    final fKey = decDoc.fields.keys.elementAt(fIdx);
                    final fVal = decDoc.fields[fKey]!;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fKey.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blueGrey.shade600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  SelectableText(
                                    fVal,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, color: Colors.blueAccent, size: 22),
                              onPressed: () => _copyToClipboard(fKey, fVal),
                              tooltip: 'Copy',
                            ),
                            IconButton(
                              icon: const Icon(Icons.share, color: Colors.teal, size: 22),
                              onPressed: () => _shareField(fKey, fVal),
                              tooltip: 'Share',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],

              // Inline Decrypted Attachments Preview
              if (decDoc.original.encryptedAttachmentPaths.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'ATTACHMENTS (TAP TO FULLSCREEN)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 75,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: decDoc.original.encryptedAttachmentPaths.length,
                    itemBuilder: (context, imgIdx) {
                      final path = decDoc.original.encryptedAttachmentPaths[imgIdx];
                      final isPdf = path.toLowerCase().endsWith('.pdf');
                      return FutureBuilder<Uint8List?>(
                        future: _vaultService.downloadAndDecryptAttachment(path),
                        builder: (context, imgSnap) {
                          if (imgSnap.connectionState == ConnectionState.waiting) {
                            return Container(
                              width: 100,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Center(
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 1.5),
                                ),
                              ),
                            );
                          }

                          final bytes = imgSnap.data;
                          if (bytes == null || bytes.isEmpty) {
                            return const SizedBox.shrink();
                          }

                          return Container(
                            width: 100,
                            margin: const EdgeInsets.only(right: 8),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                GestureDetector(
                                  onTap: () => _showFullscreenFile(bytes, path, isPdf),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: isPdf
                                        ? Container(
                                            color: Colors.red.shade50,
                                            child: const Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.picture_as_pdf, color: Colors.red, size: 24),
                                                SizedBox(height: 2),
                                                Text(
                                                  'PDF',
                                                  style: TextStyle(fontSize: 9, color: Colors.red, fontWeight: FontWeight.bold),
                                                ),
                                              ],
                                            ),
                                          )
                                        : Image.memory(
                                            bytes,
                                            fit: BoxFit.cover,
                                          ),
                                  ),
                                ),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: GestureDetector(
                                    onTap: () => _shareFileDirectly(bytes, path, isPdf),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.6),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.share, color: Colors.white, size: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showFullscreenFile(Uint8List fileBytes, String storagePath, bool isPdf) {
    final name = storagePath.split('/').last;
    var cleanName = name.replaceAll('_-_', ' - ').replaceAll('_', ' ');
    final extIndex = cleanName.lastIndexOf('.');
    if (extIndex != -1) {
      final ext = cleanName.substring(extIndex);
      var nameWithoutExt = cleanName.substring(0, extIndex);
      nameWithoutExt = nameWithoutExt.replaceAll(RegExp(r'\s\d+\s\d+$'), '');
      cleanName = '$nameWithoutExt$ext';
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullscreenFileViewer(
          fileBytes: fileBytes,
          title: cleanName,
          isPdf: isPdf,
        ),
      ),
    );
  }

  void _shareFileDirectly(Uint8List fileBytes, String storagePath, bool isPdf) async {
    try {
      final name = storagePath.split('/').last;
      var cleanName = name.replaceAll('_-_', ' - ').replaceAll('_', ' ');
      final extIndex = cleanName.lastIndexOf('.');
      if (extIndex != -1) {
        final ext = cleanName.substring(extIndex);
        var nameWithoutExt = cleanName.substring(0, extIndex);
        nameWithoutExt = nameWithoutExt.replaceAll(RegExp(r'\s\d+\s\d+$'), '');
        cleanName = '$nameWithoutExt$ext';
      }

      if (kIsWeb) {
        final mime = isPdf ? 'application/pdf' : 'image/jpeg';
        final base64Data = base64Encode(fileBytes);
        final url = 'data:$mime;base64,$base64Data';
        await launchUrl(Uri.parse(url));
        return;
      }
      
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/$cleanName';
      final file = File(tempPath);
      await file.writeAsBytes(fileBytes);
      
      await Share.shareXFiles([XFile(tempPath)], text: cleanName);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sharing: $e')),
      );
    }
  }

  void _deleteDocument(SecureDocument doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Document?'),
        content: const Text(
          'This will permanently delete this document and all its encrypted attachments. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      try {
        await _vaultService.deleteDocument(doc);
        if (mounted) {
          Navigator.pop(context); // Pop loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Document deleted successfully.'), backgroundColor: Colors.red),
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context); // Pop loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting document: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shield_outlined, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text(
            'Your secure vault is empty.',
            style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          const Text(
            'Secure cards, IDs, and financial files locally.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AddDocumentScreen()),
              );
            },
            icon: const Icon(Icons.add_moderator),
            label: const Text('Add First Document'),
          ),
        ],
      ),
    );
  }

  Future<List<DecryptedDocument>> _decryptAllDocuments(List<SecureDocument> docs) async {
    final List<DecryptedDocument?> decryptedList = await Future.wait(
      docs.map((doc) => _vaultService.decryptDocument(doc)),
    );

    return decryptedList.whereType<DecryptedDocument>().toList();
  }

  bool _areRawDocsEqual(List<SecureDocument> a, List<SecureDocument> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].lastUpdated != b[i].lastUpdated) {
        return false;
      }
    }
    return true;
  }
}
