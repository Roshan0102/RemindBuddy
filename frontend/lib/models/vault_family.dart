import 'package:cloud_firestore/cloud_firestore.dart';

class VirtualProfile {
  final String id;
  final String name;
  final String createdBy;

  VirtualProfile({
    required this.id,
    required this.name,
    required this.createdBy,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'createdBy': createdBy,
      };

  factory VirtualProfile.fromMap(Map<String, dynamic> map) => VirtualProfile(
        id: map['id'] ?? '',
        name: map['name'] ?? '',
        createdBy: map['createdBy'] ?? '',
      );
}

class VaultFamily {
  final String id;
  final String name;
  final List<String> adminUids;
  final List<String> collaboratorUids;
  final List<Map<String, dynamic>> pendingInvites;
  final List<VirtualProfile> virtualProfiles;
  final DateTime? createdAt;

  VaultFamily({
    required this.id,
    required this.name,
    required this.adminUids,
    required this.collaboratorUids,
    required this.pendingInvites,
    required this.virtualProfiles,
    this.createdAt,
  });

  factory VaultFamily.fromMap(String id, Map<String, dynamic> map) {
    final profilesRaw = List<Map<String, dynamic>>.from(map['virtualProfiles'] ?? []);
    final profiles = profilesRaw.map((p) => VirtualProfile.fromMap(p)).toList();

    return VaultFamily(
      id: id,
      name: map['name'] ?? 'Family',
      adminUids: List<String>.from(map['adminUids'] ?? []),
      collaboratorUids: List<String>.from(map['collaboratorUids'] ?? []),
      pendingInvites: List<Map<String, dynamic>>.from(map['pendingInvites'] ?? []),
      virtualProfiles: profiles,
      createdAt: map['createdAt'] is Timestamp ? (map['createdAt'] as Timestamp).toDate() : null,
    );
  }
}
