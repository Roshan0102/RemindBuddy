import 'package:cloud_firestore/cloud_firestore.dart';

class ResumeProfile {
  final String id;
  final String title; // e.g. "DevOps & Cloud Engineer"
  final List<String> targetRoles; // e.g. ["DevOps", "Cloud", "SRE", "Docker", "Kubernetes", "AWS"]
  final String fileName; // e.g. "Candidate_Resume.pdf"
  final String base64; // PDF base64 string
  final bool isDefault;
  final DateTime updatedAt;

  ResumeProfile({
    required this.id,
    required this.title,
    required this.targetRoles,
    required this.fileName,
    required this.base64,
    this.isDefault = false,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'targetRoles': targetRoles,
      'fileName': fileName,
      'base64': base64,
      'isDefault': isDefault,
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  factory ResumeProfile.fromMap(Map<String, dynamic> map, String docId) {
    DateTime parsedDate = DateTime.now();
    final timeVal = map['updatedAt'];
    if (timeVal is Timestamp) {
      parsedDate = timeVal.toDate();
    } else if (timeVal is String) {
      parsedDate = DateTime.tryParse(timeVal) ?? DateTime.now();
    }

    final rawRoles = map['targetRoles'];
    List<String> parsedRoles = [];
    if (rawRoles is List) {
      parsedRoles = rawRoles.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    } else if (rawRoles is String) {
      parsedRoles = rawRoles.split(',').map((e) => e.trim()).where((s) => s.isNotEmpty).toList();
    }

    return ResumeProfile(
      id: docId.isNotEmpty ? docId : (map['id'] ?? ''),
      title: (map['title'] ?? map['name'] ?? 'Resume Profile').toString(),
      targetRoles: parsedRoles,
      fileName: (map['fileName'] ?? 'Resume.pdf').toString(),
      base64: (map['base64'] ?? '').toString(),
      isDefault: map['isDefault'] == true,
      updatedAt: parsedDate,
    );
  }

  ResumeProfile copyWith({
    String? id,
    String? title,
    List<String>? targetRoles,
    String? fileName,
    String? base64,
    bool? isDefault,
    DateTime? updatedAt,
  }) {
    return ResumeProfile(
      id: id ?? this.id,
      title: title ?? this.title,
      targetRoles: targetRoles ?? this.targetRoles,
      fileName: fileName ?? this.fileName,
      base64: base64 ?? this.base64,
      isDefault: isDefault ?? this.isDefault,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
