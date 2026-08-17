import 'package:flutter/material.dart';
import '../models/family_member.dart';
import '../models/secure_document.dart';
import '../services/vault_service.dart';
import 'add_document_screen.dart';

class FamilyManagementScreen extends StatefulWidget {
  const FamilyManagementScreen({super.key});

  @override
  State<FamilyManagementScreen> createState() => _FamilyManagementScreenState();
}

class _FamilyManagementScreenState extends State<FamilyManagementScreen> {
  final VaultService _vaultService = VaultService();
  final _nameController = TextEditingController();
  String _selectedRelationship = 'Spouse';
  int _selectedColorValue = 0xFF3F51B5; // Default Indigo

  final List<String> _relationships = [
    'Spouse',
    'Father',
    'Mother',
    'Child',
    'Brother',
    'Sister',
    'Other'
  ];

  final List<int> _avatarColors = [
    0xFFE91E63, // Pink
    0xFF9C27B0, // Purple
    0xFF673AB7, // Deep Purple
    0xFF3F51B5, // Indigo
    0xFF2196F3, // Blue
    0xFF009688, // Teal
    0xFF4CAF50, // Green
    0xFFFF9800, // Orange
    0xFF607D8B, // Blue Grey
  ];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _showAddEditMemberDialog({FamilyMember? member}) {
    final isEditing = member != null;
    if (isEditing) {
      _nameController.text = member.name;
      _selectedRelationship = member.relationship;
      _selectedColorValue = member.avatarColorValue;
    } else {
      _nameController.clear();
      _selectedRelationship = 'Spouse';
      _selectedColorValue = _avatarColors[0];
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(isEditing ? 'Edit Family Profile' : 'Add Virtual Family Member'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Member Name',
                        hintText: 'e.g. Aarav, Ramesh, Anita',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _selectedRelationship,
                      decoration: InputDecoration(
                        labelText: 'Relationship',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.people),
                      ),
                      items: _relationships.map((r) {
                        return DropdownMenuItem(value: r, child: Text(r));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => _selectedRelationship = val);
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Choose Theme Color',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _avatarColors.map((colorVal) {
                        final isSelected = _selectedColorValue == colorVal;
                        return GestureDetector(
                          onTap: () {
                            setDialogState(() => _selectedColorValue = colorVal);
                          },
                          child: CircleAvatar(
                            backgroundColor: Color(colorVal),
                            radius: 18,
                            child: isSelected
                                ? const Icon(Icons.check, color: Colors.white, size: 18)
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    final name = _nameController.text.trim();
                    if (name.isEmpty) return;

                    if (isEditing) {
                      await _vaultService.updateFamilyMember(
                        FamilyMember(
                          id: member.id,
                          name: name,
                          relationship: _selectedRelationship,
                          avatarColorValue: _selectedColorValue,
                        ),
                      );
                    } else {
                      await _vaultService.addFamilyMember(
                        name,
                        _selectedRelationship,
                        _selectedColorValue,
                      );
                    }

                    if (mounted) Navigator.pop(context);
                  },
                  child: Text(isEditing ? 'Save' : 'Add Profile'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDelete(FamilyMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${member.name}?'),
        content: Text(
          'This will permanently delete profile "${member.name}". Documents tagged with this profile will remain in your vault under General.',
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
      await _vaultService.deleteFamilyMember(member.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('👨‍👩‍👧 Family Member Profiles'),
      ),
      body: StreamBuilder<List<FamilyMember>>(
        stream: _vaultService.getFamilyMembers(),
        builder: (context, memberSnapshot) {
          if (memberSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final members = memberSnapshot.data ?? [];

          return StreamBuilder<List<SecureDocument>>(
            stream: _vaultService.getSecureDocuments(),
            builder: (context, docSnapshot) {
              final docs = docSnapshot.data ?? [];

              // Map memberId to count of documents
              final Map<String, int> docCounts = {};
              for (var doc in docs) {
                docCounts[doc.memberId] = (docCounts[doc.memberId] ?? 0) + 1;
              }

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Info Card Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.deepPurple.shade700, Colors.indigo.shade600],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.indigo.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.family_restroom_rounded, color: Colors.white, size: 28),
                            SizedBox(width: 10),
                            Text(
                              'Virtual Family Members',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Create profiles for family members without app accounts (e.g. spouse, children, parents). Store & encrypt their Aadhar, Passport, and Health IDs in one place.',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Chip(
                              avatar: const Icon(Icons.people, size: 16, color: Colors.indigo),
                              label: Text(
                                '${members.length} Profiles',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              backgroundColor: Colors.white,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (members.isEmpty) ...[
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40.0),
                        child: Column(
                          children: [
                            Icon(Icons.person_add_alt_1_rounded, size: 70, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            const Text(
                              'No family profiles created yet.',
                              style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Tap "+ Add Member" to add your spouse, kids, or parents.',
                              style: TextStyle(fontSize: 13, color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: () => _showAddEditMemberDialog(),
                              icon: const Icon(Icons.add),
                              label: const Text('Add First Family Profile'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: members.length,
                      itemBuilder: (context, index) {
                        final member = members[index];
                        final count = docCounts[member.id] ?? 0;

                        return Card(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 26,
                                  backgroundColor: Color(member.avatarColorValue),
                                  child: Text(
                                    member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        member.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 17,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Color(member.avatarColorValue).withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              member.relationship,
                                              style: TextStyle(
                                                color: Color(member.avatarColorValue),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '$count ${count == 1 ? 'Doc' : 'Docs'}',
                                            style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_moderator, color: Colors.indigo),
                                  tooltip: 'Add Document for ${member.name}',
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => const AddDocumentScreen(),
                                      ),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blue),
                                  onPressed: () => _showAddEditMemberDialog(member: member),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                  onPressed: () => _confirmDelete(member),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditMemberDialog(),
        icon: const Icon(Icons.person_add),
        label: const Text('Add Family Member'),
      ),
    );
  }
}
