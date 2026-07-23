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
import '../services/encryption_service.dart';
import '../models/secure_document.dart';
import '../models/vault_collaborator.dart';
import '../services/vault_service.dart';
import 'vault_collaboration_screen.dart';
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
  final TextEditingController _searchController = TextEditingController();
  List<SecureDocument>? _previousRawDocs;
  Future<List<DecryptedDocument>>? _decryptionFuture;

  String _searchQuery = '';
  String? _selectedMemberId; // null means "All Members"
  String _selectedCategory = 'All'; // "All" or a specific category

  Map<String, VaultCollaborator> _collaboratorsMap = {};

  @override
  void initState() {
    super.initState();
    _loadCollaborators();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase().trim();
      });
    });
  }

  @override
  void dispose() {
    _collaboratorSubscription?.cancel();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🔒 Secure Document Vault'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const VaultCollaborationScreen()),
              );
            },
            tooltip: 'Vault Collaboration',
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

                    // Apply filters (Selected Member, Category, Search Query)
                    final filteredDocs = decDocs.where((doc) {
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

                    return Column(
                      children: [
                        // Filters row
                        Padding(
                          padding: const EdgeInsets.only(left: 12.0, right: 12.0, bottom: 8.0),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                // Member Filter
                                DropdownButton<String>(
                                  value: _selectedMemberId,
                                  hint: const Text('All Vault Members'),
                                  items: [
                                    const DropdownMenuItem<String>(
                                      value: null,
                                      child: Text('All Vault Members'),
                                    ),
                                    ..._collaboratorsMap.values.map((c) {
                                      return DropdownMenuItem<String>(
                                        value: c.uid,
                                        child: Text(c.isSelf ? 'Myself (@${c.username})' : '@${c.username}'),
                                      );
                                    }),
                                  ],
                                  onChanged: (val) {
                                    setState(() {
                                      _selectedMemberId = val;
                                    });
                                  },
                                ),
                                const SizedBox(width: 16),
                                // Category Filter (Using dynamicCategories!)
                                DropdownButton<String>(
                                  value: _selectedCategory,
                                  items: dynamicCategories.map((c) {
                                    return DropdownMenuItem<String>(
                                      value: c,
                                      child: Text(c),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    setState(() {
                                      _selectedCategory = val ?? 'All';
                                    });
                                  },
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
                                    final owner = _collaboratorsMap[decDoc.original.memberId];
                                    return _buildDocumentCard(decDoc, owner);
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

  Widget _buildDocumentCard(DecryptedDocument decDoc, VaultCollaborator? owner) {
    final ownerName = owner != null
        ? (owner.isSelf ? 'Myself (@${owner.username})' : '@${owner.username}')
        : 'Unknown';
    final avatarColor = owner?.avatarColorValue ?? 0xFF9E9E9E;

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
                      owner != null && owner.username.isNotEmpty
                          ? owner.username.substring(0, 1).toUpperCase()
                          : '?',
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
    final List<Future<DecryptedDocument>> futures = docs.map((doc) {
      return _vaultService.decryptDocument(doc);
    }).toList();

    return Future.wait(futures);
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
