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
  final String? modelUsed;
  final String? responseType; // 'interview_invite', 'assessment', 'hr_query', 'acknowledgment', 'rejection', 'other'
  final DateTime? replyReceivedAt;
  final String? replySender;
  final String? replySubject;
  final String? replySnippet;
  final String? replyBodyPreview;
  final String? actionRequired;
  final String? resumeProfileName;
  final bool isReplyDismissed;
  final bool isBounced;

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
    this.modelUsed,
    this.responseType,
    this.replyReceivedAt,
    this.replySender,
    this.replySubject,
    this.replySnippet,
    this.replyBodyPreview,
    this.actionRequired,
    this.resumeProfileName,
    this.isReplyDismissed = false,
    this.isBounced = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'jobTitle': jobTitle,
      'companyName': companyName,
      'recipientEmail': recipientEmail,
      'extractedSkills': extractedSkills,
      'generatedSubject': generatedSubject,
      'subject': generatedSubject,
      'generatedCoverLetter': generatedCoverLetter,
      'coverLetter': generatedCoverLetter,
      'status': status,
      'appliedAt': Timestamp.fromDate(appliedAt),
      'posterImageUrls': posterImageUrls,
      'errorMessage': errorMessage,
      'isAutoApplied': isAutoApplied,
      'location': location,
      'experienceRequired': experienceRequired,
      'sourcePlatform': sourcePlatform,
      'modelUsed': modelUsed,
      'responseType': responseType,
      'replyReceivedAt': replyReceivedAt != null ? Timestamp.fromDate(replyReceivedAt!) : null,
      'replySender': replySender,
      'replySubject': replySubject,
      'replySnippet': replySnippet,
      'replyBodyPreview': replyBodyPreview,
      'actionRequired': actionRequired,
      'resumeProfileName': resumeProfileName,
      'isReplyDismissed': isReplyDismissed,
      'replyDismissed': isReplyDismissed,
      'isBounced': isBounced,
    };
  }

  Map<String, dynamic> toJson() {
    final map = toMap();
    map['appliedAt'] = appliedAt.toIso8601String();
    if (replyReceivedAt != null) {
      map['replyReceivedAt'] = replyReceivedAt!.toIso8601String();
    }
    return map;
  }

  factory JobApplication.fromJson(Map<String, dynamic> json) {
    return JobApplication.fromMap(json, (json['id'] ?? '').toString());
  }

  factory JobApplication.fromMap(Map<String, dynamic> map, String docId) {
    DateTime parsedDate = DateTime.now();
    final timeVal = map['appliedAt'];
    if (timeVal is Timestamp) {
      parsedDate = timeVal.toDate();
    } else if (timeVal is String) {
      parsedDate = DateTime.tryParse(timeVal) ?? DateTime.now();
    }

    DateTime? parsedReplyDate;
    final replyTimeVal = map['replyReceivedAt'];
    if (replyTimeVal is Timestamp) {
      parsedReplyDate = replyTimeVal.toDate();
    } else if (replyTimeVal is String) {
      parsedReplyDate = DateTime.tryParse(replyTimeVal);
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

    final String subject = (map['generatedSubject'] ?? map['subject'] ?? '').toString();
    final String coverLetter = (map['generatedCoverLetter'] ?? map['coverLetter'] ?? map['body'] ?? '').toString();

    final String resolvedTitle = (map['jobTitle'] ?? map['role'] ?? map['title'] ?? 'Unknown Position').toString();
    final String resolvedCompany = (map['companyName'] ?? map['company'] ?? 'Unknown Company').toString();
    final String resolvedEmail = (map['recipientEmail'] ?? map['contactEmail'] ?? map['email'] ?? '').toString();

    return JobApplication(
      id: docId.isNotEmpty ? docId : (map['id'] ?? '').toString(),
      jobTitle: resolvedTitle.isNotEmpty ? resolvedTitle : 'Unknown Position',
      companyName: resolvedCompany.isNotEmpty ? resolvedCompany : 'Unknown Company',
      recipientEmail: resolvedEmail,
      extractedSkills: parsedSkills,
      generatedSubject: subject,
      generatedCoverLetter: coverLetter,
      status: (map['status'] ?? 'extracted').toString(),
      appliedAt: parsedDate,
      posterImageUrls: parsedImages,
      errorMessage: map['errorMessage']?.toString(),
      isAutoApplied: map['isAutoApplied'] == true || map['autoApplied'] == true,
      location: map['location'] as String?,
      experienceRequired: map['experienceRequired'] as String?,
      sourcePlatform: map['sourcePlatform'] as String?,
      modelUsed: map['modelUsed'] as String?,
      responseType: map['responseType'] as String?,
      replyReceivedAt: parsedReplyDate,
      replySender: map['replySender'] as String?,
      replySubject: map['replySubject'] as String?,
      replySnippet: map['replySnippet'] as String?,
      replyBodyPreview: map['replyBodyPreview'] as String?,
      actionRequired: map['actionRequired'] as String?,
      resumeProfileName: map['resumeProfileName'] as String?,
      isReplyDismissed: map['replyDismissed'] == true || map['isReplyDismissed'] == true,
      isBounced: map['isBounced'] == true || map['emailBounced'] == true || map['responseType'] == 'bounced' || map['status'] == 'bounced',
    );
  }
}
