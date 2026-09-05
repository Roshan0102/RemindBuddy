import 'package:cloud_firestore/cloud_firestore.dart';

class NetworkingLead {
  final String id;
  final String name;
  final String currentRole;
  final String companyName;
  final String location;
  final String linkedinUrl;
  final String? email;
  final String category; // 'engineering_manager', 'founder', 'talent_acquisition'
  final String connectionNote; // <= 300 characters for LinkedIn connection note
  final String fullPitch; // Complete networking introductory pitch / cold email
  final String status; // 'discovered', 'note_sent', 'connected', 'replied'
  final DateTime discoveredAt;

  NetworkingLead({
    required this.id,
    required this.name,
    required this.currentRole,
    required this.companyName,
    required this.location,
    required this.linkedinUrl,
    this.email,
    required this.category,
    required this.connectionNote,
    required this.fullPitch,
    this.status = 'discovered',
    required this.discoveredAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'currentRole': currentRole,
      'companyName': companyName,
      'location': location,
      'linkedinUrl': linkedinUrl,
      'email': email,
      'category': category,
      'connectionNote': connectionNote,
      'fullPitch': fullPitch,
      'status': status,
      'discoveredAt': Timestamp.fromDate(discoveredAt),
    };
  }

  factory NetworkingLead.fromMap(Map<String, dynamic> map, String docId) {
    DateTime parsedDiscoveredAt = DateTime.now();
    if (map['discoveredAt'] != null) {
      if (map['discoveredAt'] is Timestamp) {
        parsedDiscoveredAt = (map['discoveredAt'] as Timestamp).toDate();
      } else if (map['discoveredAt'] is String) {
        parsedDiscoveredAt = DateTime.tryParse(map['discoveredAt']) ?? DateTime.now();
      }
    }

    return NetworkingLead(
      id: docId,
      name: (map['name'] ?? 'Tech Leader').toString(),
      currentRole: (map['currentRole'] ?? map['role'] ?? 'Hiring Leader').toString(),
      companyName: (map['companyName'] ?? map['company'] ?? 'Tech Company').toString(),
      location: (map['location'] ?? 'Bengaluru, India').toString(),
      linkedinUrl: (map['linkedinUrl'] ?? '').toString(),
      email: map['email'] != null && map['email'].toString().isNotEmpty
          ? map['email'].toString()
          : null,
      category: (map['category'] ?? 'engineering_manager').toString(),
      connectionNote: (map['connectionNote'] ?? '').toString(),
      fullPitch: (map['fullPitch'] ?? map['pitch'] ?? '').toString(),
      status: (map['status'] ?? 'discovered').toString(),
      discoveredAt: parsedDiscoveredAt,
    );
  }

  NetworkingLead copyWith({
    String? id,
    String? name,
    String? currentRole,
    String? companyName,
    String? location,
    String? linkedinUrl,
    String? email,
    String? category,
    String? connectionNote,
    String? fullPitch,
    String? status,
    DateTime? discoveredAt,
  }) {
    return NetworkingLead(
      id: id ?? this.id,
      name: name ?? this.name,
      currentRole: currentRole ?? this.currentRole,
      companyName: companyName ?? this.companyName,
      location: location ?? this.location,
      linkedinUrl: linkedinUrl ?? this.linkedinUrl,
      email: email ?? this.email,
      category: category ?? this.category,
      connectionNote: connectionNote ?? this.connectionNote,
      fullPitch: fullPitch ?? this.fullPitch,
      status: status ?? this.status,
      discoveredAt: discoveredAt ?? this.discoveredAt,
    );
  }
}
