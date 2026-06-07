import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../models/family_member.dart';
import '../models/secure_document.dart';
import '../services/vault_service.dart';
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
  StreamSubscription? _familySubscription;

  String _searchQuery = '';
  String? _selectedMemberId; // null means "All Members"
  String _selectedCategory = 'All'; // "All" or a specific category

  final List<String> _categories = [
    'All',
    'Identity Cards',
    'Financial',
    'Health & Medical',
    'Insurance',
    'Others'
  ];

  Map<String, FamilyMember> _familyMembersMap = {};

  @override
  void initState() {
    super.initState();
    _loadFamilyMembers();
  }

  @override
  void dispose() {
    _familySubscription?.cancel();
    super.dispose();
  }

  void _loadFamilyMembers() {
    _familySubscription?.cancel();
    _familySubscription = _vaultService.getFamilyMembers().listen((list) {
      if (mounted) {
        setState(() {
          _familyMembersMap = {for (var m in list) m.id: m};
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🔒 Secure Document Vault'),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_outline),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const FamilyManagementScreen()),
              );
            },
            tooltip: 'Manage Family Members',
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Search Bar & Filters
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                TextField(
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val.toLowerCase().trim();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search documents, Aadhar, accounts...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              FocusScope.of(context).unfocus();
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                          )
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
                const SizedBox(height: 10),
                // Horizontal Filters
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // Member Filter
                      DropdownButton<String>(
                        value: _selectedMemberId,
                        hint: const Text('All Members'),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('All Family Members'),
                          ),
                          ..._familyMembersMap.values.map((m) {
                            return DropdownMenuItem<String>(
                              value: m.id,
                              child: Text(m.name),
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
                      // Category Filter
                      DropdownButton<String>(
                        value: _selectedCategory,
                        items: _categories.map((c) {
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
              ],
            ),
          ),

          // 2. Document Stream
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

                // Decrypt raw documents to search fields in memory
                return FutureBuilder<List<DecryptedDocument>>(
                  future: _decryptAllDocuments(rawDocs),
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

                      // Filter by Search query (looks in title, field keys, and field values)
                      if (_searchQuery.isNotEmpty) {
                        final titleMatch = doc.title.toLowerCase().contains(_searchQuery);
                        final fieldsKeyMatch = doc.fields.keys.any((k) => k.toLowerCase().contains(_searchQuery));
                        final fieldsValueMatch = doc.fields.values.any((v) => v.toLowerCase().contains(_searchQuery));
                        return titleMatch || fieldsKeyMatch || fieldsValueMatch;
                      }

                      return true;
                    }).toList();

                    if (filteredDocs.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24.0),
                          child: Text(
                            'No documents match your search.',
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: filteredDocs.length,
                      itemBuilder: (context, index) {
                        final decDoc = filteredDocs[index];
                        final owner = _familyMembersMap[decDoc.original.memberId];
                        return _buildDocumentCard(decDoc, owner);
                      },
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

  Widget _buildDocumentCard(DecryptedDocument decDoc, FamilyMember? owner) {
    final ownerName = owner?.name ?? 'Unknown';
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
                      ownerName.isNotEmpty ? ownerName.substring(0, 1).toUpperCase() : '?',
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
                                      fontSize: 18, // Large text size for readability by elderly parents
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

              // Inline Decrypted Image Attachments Preview
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

                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => FullscreenImageViewer(
                                    imageBytes: bytes,
                                    title: '${decDoc.title}_Scan_${imgIdx + 1}',
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              width: 100,
                              margin: const EdgeInsets.only(right: 8),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.memory(
                                  bytes,
                                  fit: BoxFit.cover,
                                ),
                              ),
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
}
