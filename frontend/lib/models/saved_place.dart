import 'package:cloud_firestore/cloud_firestore.dart';

class SavedPlace {
  final String? id;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final String iconName;
  final String? address;
  final DateTime? createdAt;

  const SavedPlace({
    this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 50.0,
    this.iconName = 'building',
    this.address,
    this.createdAt,
  });

  factory SavedPlace.fromMap(Map<String, dynamic> map, String docId) {
    DateTime? created;
    if (map['createdAt'] is Timestamp) {
      created = (map['createdAt'] as Timestamp).toDate();
    } else if (map['createdAt'] is String) {
      created = DateTime.tryParse(map['createdAt'] as String);
    }

    return SavedPlace(
      id: docId,
      name: map['name'] as String? ?? 'Unnamed Place',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      radiusMeters: (map['radiusMeters'] as num?)?.toDouble() ?? 50.0,
      iconName: map['iconName'] as String? ?? 'building',
      address: map['address'] as String?,
      createdAt: created,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'radiusMeters': radiusMeters,
      'iconName': iconName,
      if (address != null && address!.isNotEmpty) 'address': address,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
    };
  }

  SavedPlace copyWith({
    String? id,
    String? name,
    double? latitude,
    double? longitude,
    double? radiusMeters,
    String? iconName,
    String? address,
    DateTime? createdAt,
  }) {
    return SavedPlace(
      id: id ?? this.id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      iconName: iconName ?? this.iconName,
      address: address ?? this.address,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
