import 'package:flutter/material.dart';
import '../models/vault_collaborator.dart';
import '../services/storage_service.dart';
import '../services/vault_service.dart';

class VaultCollaborationScreen extends StatefulWidget {
  const VaultCollaborationScreen({super.key});

  @override
  State<VaultCollaborationScreen> createState() => _VaultCollaborationScreenState();
}

class _VaultCollaborationScreenState extends State<VaultCollaborationScreen> {
  final VaultService _vaultService = VaultService();
  final StorageService _storageService = StorageService();

  final TextEditingController _usernameController = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  void _sendRequest(String targetUsername) async {
    final cleanUsername = targetUsername.trim();
    if (cleanUsername.isEmpty) return;

    setState(() => _isSending = true);

    try {
      await _vaultService.sendVaultCollaborationRequest(cleanUsername);
      _usernameController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Vault collaboration request sent to @$cleanUsername!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ $errorMsg'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _showUserPickerModal() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return FutureBuilder<List<Map<String, String>>>(
              future: _storageService.getAllUsers(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final users = snapshot.data ?? [];
                if (users.isEmpty) {
                  return const Center(
                    child: Text('No other registered users found.'),
                  );
                }

                return Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        'Select App User to Invite',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: users.length,
                        itemBuilder: (context, index) {
                          final u = users[index];
                          final uname = u['username'] ?? '';
                          final colorVal = VaultCollaborator.generateColorForUser(uname);

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Color(colorVal),
                              child: Text(
                                uname.isNotEmpty ? uname[0].toUpperCase() : 'U',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                            title: Text('@$uname', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(u['email'] ?? ''),
                            trailing: const Icon(Icons.send_rounded, color: Colors.blueAccent),
                            onTap: () {
                              Navigator.pop(context);
                              _sendRequest(uname);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _confirmRemoveCollaborator(VaultCollaborator collaborator) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove @${collaborator.username}?'),
        content: Text(
          'This will revoke shared Vault access between you and @${collaborator.username}. Documents will no longer be shared between accounts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _vaultService.removeVaultCollaborator(collaborator.collaborationId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Removed @${collaborator.username} from Vault family.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error removing collaborator: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('👥 Vault Collaboration'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // 1. Send Request Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Invite Family / App User',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Collaborate and share secure vault documents bi-directionally with another RemindBuddy app user.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _usernameController,
                          decoration: InputDecoration(
                            hintText: 'Enter username (e.g. roshan)',
                            prefixText: '@ ',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.contacts, color: Colors.blueAccent),
                        onPressed: _showUserPickerModal,
                        tooltip: 'Select from user list',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSending ? null : () => _sendRequest(_usernameController.text),
                      icon: _isSending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded),
                      label: const Text('Send Collaboration Request'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 2. Incoming Collaboration Requests Section
          StreamBuilder<List<VaultCollaborationRequest>>(
            stream: _vaultService.getIncomingRequestsStream(),
            builder: (context, snapshot) {
              final requests = snapshot.data ?? [];
              if (requests.isEmpty) return const SizedBox.shrink();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'INCOMING REQUESTS',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 8),
                  ...requests.map((req) {
                    final colorVal = VaultCollaborator.generateColorForUser(req.senderUsername);
                    return Card(
                      color: Colors.amber.shade50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: Colors.amber.shade300),
                      ),
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Color(colorVal),
                          child: Text(
                            req.senderUsername.isNotEmpty ? req.senderUsername[0].toUpperCase() : 'U',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(
                          '@${req.senderUsername}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text('Wants to collaborate on Secure Vault'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () => _vaultService.respondToVaultCollaborationRequest(req.id, false),
                              tooltip: 'Reject',
                            ),
                            IconButton(
                              icon: const Icon(Icons.check_circle, color: Colors.green, size: 28),
                              onPressed: () => _vaultService.respondToVaultCollaborationRequest(req.id, true),
                              tooltip: 'Accept',
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),

          // 3. Outgoing Collaboration Requests Section
          StreamBuilder<List<VaultCollaborationRequest>>(
            stream: _vaultService.getOutgoingRequestsStream(),
            builder: (context, snapshot) {
              final requests = snapshot.data ?? [];
              if (requests.isEmpty) return const SizedBox.shrink();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'OUTGOING PENDING REQUESTS',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 8),
                  ...requests.map((req) {
                    final colorVal = VaultCollaborator.generateColorForUser(req.receiverUsername);
                    return Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Color(colorVal),
                          child: Text(
                            req.receiverUsername.isNotEmpty ? req.receiverUsername[0].toUpperCase() : 'U',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text('@${req.receiverUsername}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: const Text('Pending acceptance...'),
                        trailing: IconButton(
                          icon: const Icon(Icons.cancel_outlined, color: Colors.grey),
                          onPressed: () => _vaultService.respondToVaultCollaborationRequest(req.id, false),
                          tooltip: 'Cancel Request',
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),

          // 4. Active Vault Collaborators / Family Members Section
          const Text(
            'ACTIVE VAULT COLLABORATORS',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey, letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<VaultCollaborator>>(
            stream: _vaultService.getVaultCollaborators(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final collaborators = snapshot.data ?? [];

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: collaborators.length,
                itemBuilder: (context, index) {
                  final c = collaborators[index];

                  return Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Color(c.avatarColorValue),
                        child: Text(
                          c.username.isNotEmpty ? c.username[0].toUpperCase() : '?',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Row(
                        children: [
                          Text('@${c.username}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          if (c.isSelf) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'YOU',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(c.isSelf ? 'Account Owner' : 'Shared Vault Member'),
                      trailing: c.isSelf
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.person_remove_outlined, color: Colors.redAccent),
                              onPressed: () => _confirmRemoveCollaborator(c),
                              tooltip: 'Remove Collaborator',
                            ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
