import 'package:cloud_firestore/cloud_firestore.dart';

class CareerPortalJob {
  final String id;
  final String jobTitle;
  final String companyName;
  final String portalType; // 'greenhouse', 'lever', 'ashby', 'workday', 'other'
  final String portalUrl;
  final String location;
  final String workplaceType; // 'remote', 'hybrid', 'on-site'
  final String experienceRequired;
  final DateTime postedAt;
  final DateTime discoveredAt;
  final int atsScore; // 0 - 100
  final List<String> matchedSkills;
  final List<String> injectedKeywords;
  final String matchReasoning;
  final String jobDescriptionSnippet;
  final String? tailoredResumePdfBase64;
  final String? tailoredResumePdfUrl;
  final String? tailoredSummary;
  final String status; // 'discovered', 'applied', 'dismissed'
  final DateTime? appliedAt;

  CareerPortalJob({
    required this.id,
    required this.jobTitle,
    required this.companyName,
    required this.portalType,
    required this.portalUrl,
    required this.location,
    required this.workplaceType,
    required this.experienceRequired,
    required this.postedAt,
    required this.discoveredAt,
    required this.atsScore,
    required this.matchedSkills,
    required this.injectedKeywords,
    required this.matchReasoning,
    required this.jobDescriptionSnippet,
    this.tailoredResumePdfBase64,
    this.tailoredResumePdfUrl,
    this.tailoredSummary,
    this.status = 'discovered',
    this.appliedAt,
  });

  factory CareerPortalJob.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return CareerPortalJob.fromJson({...data, 'id': doc.id});
  }

  factory CareerPortalJob.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String && val.isNotEmpty) {
        return DateTime.tryParse(val) ?? DateTime.now();
      }
      return DateTime.now();
    }

    DateTime? parseNullableDate(dynamic val) {
      if (val == null) return null;
      if (val is Timestamp) return val.toDate();
      if (val is String && val.isNotEmpty) {
        return DateTime.tryParse(val);
      }
      return null;
    }

    return CareerPortalJob(
      id: json['id']?.toString() ?? '',
      jobTitle: json['jobTitle']?.toString() ?? 'Job Opening',
      companyName: json['companyName']?.toString() ?? 'Company',
      portalType: json['portalType']?.toString().toLowerCase() ?? 'other',
      portalUrl: json['portalUrl']?.toString() ?? '',
      location: json['location']?.toString() ?? 'Remote',
      workplaceType: json['workplaceType']?.toString() ?? 'remote',
      experienceRequired: json['experienceRequired']?.toString() ?? '1-3 years',
      postedAt: parseDate(json['postedAt']),
      discoveredAt: parseDate(json['discoveredAt']),
      atsScore: (json['atsScore'] is num) ? (json['atsScore'] as num).toInt() : 85,
      matchedSkills: (json['matchedSkills'] is List)
          ? (json['matchedSkills'] as List).map((e) => e.toString()).toList()
          : [],
      injectedKeywords: (json['injectedKeywords'] is List)
          ? (json['injectedKeywords'] as List).map((e) => e.toString()).toList()
          : [],
      matchReasoning: json['matchReasoning']?.toString() ?? '',
      jobDescriptionSnippet: json['jobDescriptionSnippet']?.toString() ?? '',
      tailoredResumePdfBase64: json['tailoredResumePdfBase64']?.toString(),
      tailoredResumePdfUrl: json['tailoredResumePdfUrl']?.toString(),
      tailoredSummary: json['tailoredSummary']?.toString(),
      status: json['status']?.toString() ?? 'discovered',
      appliedAt: parseNullableDate(json['appliedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'jobTitle': jobTitle,
      'companyName': companyName,
      'portalType': portalType,
      'portalUrl': portalUrl,
      'location': location,
      'workplaceType': workplaceType,
      'experienceRequired': experienceRequired,
      'postedAt': postedAt.toIso8601String(),
      'discoveredAt': Timestamp.fromDate(discoveredAt),
      'atsScore': atsScore,
      'matchedSkills': matchedSkills,
      'injectedKeywords': injectedKeywords,
      'matchReasoning': matchReasoning,
      'jobDescriptionSnippet': jobDescriptionSnippet,
      'tailoredResumePdfBase64': tailoredResumePdfBase64,
      'tailoredResumePdfUrl': tailoredResumePdfUrl,
      'tailoredSummary': tailoredSummary,
      'status': status,
      'appliedAt': appliedAt != null ? Timestamp.fromDate(appliedAt!) : null,
    };
  }

  CareerPortalJob copyWith({
    String? status,
    DateTime? appliedAt,
  }) {
    return CareerPortalJob(
      id: id,
      jobTitle: jobTitle,
      companyName: companyName,
      portalType: portalType,
      portalUrl: portalUrl,
      location: location,
      workplaceType: workplaceType,
      experienceRequired: experienceRequired,
      postedAt: postedAt,
      discoveredAt: discoveredAt,
      atsScore: atsScore,
      matchedSkills: matchedSkills,
      injectedKeywords: injectedKeywords,
      matchReasoning: matchReasoning,
      jobDescriptionSnippet: jobDescriptionSnippet,
      tailoredResumePdfBase64: tailoredResumePdfBase64,
      tailoredResumePdfUrl: tailoredResumePdfUrl,
      tailoredSummary: tailoredSummary,
      status: status ?? this.status,
      appliedAt: appliedAt ?? this.appliedAt,
    );
  }
}
