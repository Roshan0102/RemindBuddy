import 'package:flutter/material.dart';

class VaultCollaborator {
  final String uid;
  final String username;
  final String email;
  final String collaborationId;
  final bool isSelf;
  final int avatarColorValue;

  VaultCollaborator({
    required this.uid,
    required this.username,
    required this.email,
    required this.collaborationId,
    this.isSelf = false,
    required this.avatarColorValue,
  });

  /// Deterministic color generation based on username string
  static int generateColorForUser(String text) {
    if (text.isEmpty) return 0xFF3F51B5;
    final List<int> palette = [
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
    int hash = 0;
    for (int i = 0; i < text.length; i++) {
      hash = text.codeUnitAt(i) + ((hash << 5) - hash);
    }
    return palette[hash.abs() % palette.length];
  }
}

class VaultCollaborationRequest {
  final String id;
  final String senderUid;
  final String senderUsername;
  final String receiverUid;
  final String receiverUsername;
  final String status; // 'pending', 'approved', 'rejected'
  final DateTime? createdAt;

  VaultCollaborationRequest({
    required this.id,
    required this.senderUid,
    required this.senderUsername,
    required this.receiverUid,
    required this.receiverUsername,
    required this.status,
    this.createdAt,
  });

  factory VaultCollaborationRequest.fromMap(String id, Map<String, dynamic> map) {
    return VaultCollaborationRequest(
      id: id,
      senderUid: (map['senderUid'] ?? '').toString(),
      senderUsername: (map['senderUsername'] ?? '').toString(),
      receiverUid: (map['receiverUid'] ?? '').toString(),
      receiverUsername: (map['receiverUsername'] ?? '').toString(),
      status: (map['status'] ?? 'pending').toString(),
      createdAt: map['createdAt'] != null
          ? (map['createdAt'] as dynamic).toDate()
          : null,
    );
  }
}
