class FamilyMember {
  final String id;
  final String name;
  final String relationship; // e.g., Self, Spouse, Father, Mother, Child, Brother, Sister, Other
  final int avatarColorValue; // Color value for the profile circle

  FamilyMember({
    required this.id,
    required this.name,
    required this.relationship,
    required this.avatarColorValue,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'relationship': relationship,
      'avatarColorValue': avatarColorValue,
    };
  }

  factory FamilyMember.fromMap(Map<String, dynamic> map) {
    return FamilyMember(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      relationship: map['relationship'] ?? '',
      avatarColorValue: map['avatarColorValue'] ?? 0xFF4CAF50,
    );
  }
}
