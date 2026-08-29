import 'package:cloud_firestore/cloud_firestore.dart';

class JobApplication {
  final String id;
  final String jobTitle;
  final String companyName;
  final String recipientEmail;
  final List<String> extractedSkills;
  final String generatedSubject;
  final String generatedCoverLetter;
  final String status; // 'extracted', 'sent', 'failed'
  final DateTime appliedAt;
  final List<String> posterImageUrls;
  final String? errorMessage;
  final bool isAutoApplied;
  final String? location;
  final String? experienceRequired;
  final String? sourcePlatform;

  JobApplication({
    required this.id,
    required this.jobTitle,
    required this.companyName,
    required this.recipientEmail,
    required this.extractedSkills,
    required this.generatedSubject,
    required this.generatedCoverLetter,
    required this.status,
    required this.appliedAt,
    this.posterImageUrls = const [],
    this.errorMessage,
    this.isAutoApplied = false,
    this.location,
    this.experienceRequired,
    this.sourcePlatform,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'jobTitle': jobTitle,
      'companyName': companyName,
      'recipientEmail': recipientEmail,
      'extractedSkills': extractedSkills,
      'generatedSubject': generatedSubject,
      'generatedCoverLetter': generatedCoverLetter,
      'status': status,
      'appliedAt': Timestamp.fromDate(appliedAt),
      'posterImageUrls': posterImageUrls,
      'errorMessage': errorMessage,
      'isAutoApplied': isAutoApplied,
      'location': location,
      'experienceRequired': experienceRequired,
      'sourcePlatform': sourcePlatform,
    };
  }

  factory JobApplication.fromMap(Map<String, dynamic> map, String docId) {
    DateTime parsedDate = DateTime.now();
    final timeVal = map['appliedAt'];
    if (timeVal is Timestamp) {
      parsedDate = timeVal.toDate();
    } else if (timeVal is String) {
      parsedDate = DateTime.tryParse(timeVal) ?? DateTime.now();
    }

    final rawSkills = map['extractedSkills'];
    List<String> parsedSkills = [];
    if (rawSkills is List) {
      parsedSkills = rawSkills.map((e) => e.toString()).toList();
    }

    final rawImages = map['posterImageUrls'];
    List<String> parsedImages = [];
    if (rawImages is List) {
      parsedImages = rawImages.map((e) => e.toString()).toList();
    }

    return JobApplication(
      id: docId,
      jobTitle: map['jobTitle'] ?? 'Unknown Position',
      companyName: map['companyName'] ?? 'Unknown Company',
      recipientEmail: map['recipientEmail'] ?? '',
      extractedSkills: parsedSkills,
      generatedSubject: map['generatedSubject'] ?? '',
      generatedCoverLetter: map['generatedCoverLetter'] ?? '',
      status: map['status'] ?? 'extracted',
      appliedAt: parsedDate,
      posterImageUrls: parsedImages,
      errorMessage: map['errorMessage'],
      isAutoApplied: map['isAutoApplied'] == true,
      location: map['location'] as String?,
      experienceRequired: map['experienceRequired'] as String?,
      sourcePlatform: map['sourcePlatform'] as String?,
    );
  }
}
