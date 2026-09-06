import 'package:cloud_firestore/cloud_firestore.dart';

class NetworkingLead {
  final String id;
  final String name;
  final String currentRole;
  final String companyName;
  final String location;
  final String linkedinUrl;
  final String? email;
  final String category; // 'founder', 'engineering_manager', 'talent_acquisition'
  final String connectionNote; // <= 300 characters for LinkedIn connection note
  final String fullPitch; // Complete networking introductory pitch / cold email
  final String status; // 'discovered', 'email_sent', 'note_sent', 'connected', 'replied'
  final DateTime discoveredAt;

  // Cold Email Dispatch & Reply Tracking
  final bool emailSent;
  final DateTime? emailSentAt;
  final String? emailSubject;
  final String? responseType; // 'interview_invite', 'assessment', 'hr_query', 'founder_chat', 'rejection', etc.
  final DateTime? replyReceivedAt;
  final String? replySender;
  final String? replySubject;
  final String? replySnippet;
  final String? replyBodyPreview;
  final String? actionRequired;
  final String? fundingStage; // 'Seed', 'Series A', 'YC-backed', 'High-Growth'
  final List<String>? techStack;

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
    this.emailSent = false,
    this.emailSentAt,
    this.emailSubject,
    this.responseType,
    this.replyReceivedAt,
    this.replySender,
    this.replySubject,
    this.replySnippet,
    this.replyBodyPreview,
    this.actionRequired,
    this.fundingStage,
    this.techStack,
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
      'emailSent': emailSent,
      'emailSentAt': emailSentAt != null ? Timestamp.fromDate(emailSentAt!) : null,
      'emailSubject': emailSubject,
      'responseType': responseType,
      'replyReceivedAt': replyReceivedAt != null ? Timestamp.fromDate(replyReceivedAt!) : null,
      'replySender': replySender,
      'replySubject': replySubject,
      'replySnippet': replySnippet,
      'replyBodyPreview': replyBodyPreview,
      'actionRequired': actionRequired,
      'fundingStage': fundingStage,
      'techStack': techStack,
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

    DateTime? parsedEmailSentAt;
    if (map['emailSentAt'] != null) {
      if (map['emailSentAt'] is Timestamp) {
        parsedEmailSentAt = (map['emailSentAt'] as Timestamp).toDate();
      } else if (map['emailSentAt'] is String) {
        parsedEmailSentAt = DateTime.tryParse(map['emailSentAt']);
      }
    }

    DateTime? parsedReplyReceivedAt;
    if (map['replyReceivedAt'] != null) {
      if (map['replyReceivedAt'] is Timestamp) {
        parsedReplyReceivedAt = (map['replyReceivedAt'] as Timestamp).toDate();
      } else if (map['replyReceivedAt'] is String) {
        parsedReplyReceivedAt = DateTime.tryParse(map['replyReceivedAt']);
      }
    }

    List<String>? parsedTechStack;
    if (map['techStack'] is List) {
      parsedTechStack = (map['techStack'] as List).map((e) => e.toString()).toList();
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
      category: (map['category'] ?? 'founder').toString(),
      connectionNote: (map['connectionNote'] ?? '').toString(),
      fullPitch: (map['fullPitch'] ?? map['pitch'] ?? '').toString(),
      status: (map['status'] ?? 'discovered').toString(),
      discoveredAt: parsedDiscoveredAt,
      emailSent: map['emailSent'] == true,
      emailSentAt: parsedEmailSentAt,
      emailSubject: map['emailSubject']?.toString(),
      responseType: map['responseType']?.toString(),
      replyReceivedAt: parsedReplyReceivedAt,
      replySender: map['replySender']?.toString(),
      replySubject: map['replySubject']?.toString(),
      replySnippet: map['replySnippet']?.toString(),
      replyBodyPreview: map['replyBodyPreview']?.toString(),
      actionRequired: map['actionRequired']?.toString(),
      fundingStage: map['fundingStage']?.toString(),
      techStack: parsedTechStack,
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
    bool? emailSent,
    DateTime? emailSentAt,
    String? emailSubject,
    String? responseType,
    DateTime? replyReceivedAt,
    String? replySender,
    String? replySubject,
    String? replySnippet,
    String? replyBodyPreview,
    String? actionRequired,
    String? fundingStage,
    List<String>? techStack,
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
      emailSent: emailSent ?? this.emailSent,
      emailSentAt: emailSentAt ?? this.emailSentAt,
      emailSubject: emailSubject ?? this.emailSubject,
      responseType: responseType ?? this.responseType,
      replyReceivedAt: replyReceivedAt ?? this.replyReceivedAt,
      replySender: replySender ?? this.replySender,
      replySubject: replySubject ?? this.replySubject,
      replySnippet: replySnippet ?? this.replySnippet,
      replyBodyPreview: replyBodyPreview ?? this.replyBodyPreview,
      actionRequired: actionRequired ?? this.actionRequired,
      fundingStage: fundingStage ?? this.fundingStage,
      techStack: techStack ?? this.techStack,
    );
  }
}
