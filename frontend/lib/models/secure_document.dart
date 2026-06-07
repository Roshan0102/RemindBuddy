class SecureDocument {
  final String id;
  final String memberId;
  final String category;
  final String encryptedTitle;
  final Map<String, String> encryptedFields; // Map of custom field labels to encrypted values
  final List<String> encryptedAttachmentPaths; // Paths to files in Firebase Storage
  final DateTime lastUpdated;

  SecureDocument({
    required this.id,
    required this.memberId,
    required this.category,
    required this.encryptedTitle,
    required this.encryptedFields,
    required this.encryptedAttachmentPaths,
    required this.lastUpdated,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'memberId': memberId,
      'category': category,
      'encryptedTitle': encryptedTitle,
      'encryptedFields': encryptedFields,
      'encryptedAttachmentPaths': encryptedAttachmentPaths,
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }

  factory SecureDocument.fromMap(Map<String, dynamic> map) {
    return SecureDocument(
      id: map['id'] ?? '',
      memberId: map['memberId'] ?? '',
      category: map['category'] ?? 'Others',
      encryptedTitle: map['encryptedTitle'] ?? '',
      encryptedFields: Map<String, String>.from(map['encryptedFields'] ?? {}),
      encryptedAttachmentPaths: List<String>.from(map['encryptedAttachmentPaths'] ?? []),
      lastUpdated: map['lastUpdated'] != null
          ? DateTime.parse(map['lastUpdated'])
          : DateTime.now(),
    );
  }
}
