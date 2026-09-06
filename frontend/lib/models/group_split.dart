import 'package:cloud_firestore/cloud_firestore.dart';

class GroupEvent {
  final String id;
  final String title;
  final List<String> members;
  final DateTime createdAt;
  final bool isArchived;
  final double totalAmount;
  final double myShare;
  final double collectedAmount;
  final bool isSettled;
  final String settledNote;
  final String linkedTxId;

  GroupEvent({
    required this.id,
    required this.title,
    required this.members,
    required this.createdAt,
    this.isArchived = false,
    this.totalAmount = 0.0,
    this.myShare = 0.0,
    this.collectedAmount = 0.0,
    this.isSettled = false,
    this.settledNote = '',
    this.linkedTxId = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'members': members,
      'createdAt': Timestamp.fromDate(createdAt),
      'isArchived': isArchived,
      'totalAmount': totalAmount,
      'myShare': myShare,
      'collectedAmount': collectedAmount,
      'isSettled': isSettled,
      'settledNote': settledNote,
      'linkedTxId': linkedTxId,
    };
  }

  factory GroupEvent.fromMap(Map<String, dynamic> map, String docId) {
    DateTime parsedDate = DateTime.now();
    final dateVal = map['createdAt'];
    if (dateVal is Timestamp) {
      parsedDate = dateVal.toDate();
    } else if (dateVal is String) {
      parsedDate = DateTime.tryParse(dateVal) ?? DateTime.now();
    }

    final rawMembers = map['members'];
    List<String> parsedMembers = [];
    if (rawMembers is List) {
      parsedMembers = rawMembers.map((e) => e.toString()).toList();
    }

    return GroupEvent(
      id: docId,
      title: map['title'] ?? 'Group Event',
      members: parsedMembers,
      createdAt: parsedDate,
      isArchived: map['isArchived'] as bool? ?? false,
      totalAmount: (map['totalAmount'] as num?)?.toDouble() ?? 0.0,
      myShare: (map['myShare'] as num?)?.toDouble() ?? 0.0,
      collectedAmount: (map['collectedAmount'] as num?)?.toDouble() ?? 0.0,
      isSettled: map['isSettled'] as bool? ?? false,
      settledNote: map['settledNote'] ?? '',
      linkedTxId: map['linkedTxId'] ?? '',
    );
  }

  GroupEvent copyWith({
    String? id,
    String? title,
    List<String>? members,
    DateTime? createdAt,
    bool? isArchived,
    double? totalAmount,
    double? myShare,
    double? collectedAmount,
    bool? isSettled,
    String? settledNote,
    String? linkedTxId,
  }) {
    return GroupEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      members: members ?? this.members,
      createdAt: createdAt ?? this.createdAt,
      isArchived: isArchived ?? this.isArchived,
      totalAmount: totalAmount ?? this.totalAmount,
      myShare: myShare ?? this.myShare,
      collectedAmount: collectedAmount ?? this.collectedAmount,
      isSettled: isSettled ?? this.isSettled,
      settledNote: settledNote ?? this.settledNote,
      linkedTxId: linkedTxId ?? this.linkedTxId,
    );
  }
}

class GroupExpense {
  final String id;
  final String groupId;
  final String description;
  final double amount;
  final String payerName;
  final List<String> involvedMembers;
  final Map<String, double> customSplit;
  final DateTime date;

  GroupExpense({
    required this.id,
    required this.groupId,
    required this.description,
    required this.amount,
    required this.payerName,
    required this.involvedMembers,
    this.customSplit = const {},
    required this.date,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'groupId': groupId,
      'description': description,
      'amount': amount,
      'payerName': payerName,
      'involvedMembers': involvedMembers,
      'customSplit': customSplit,
      'date': Timestamp.fromDate(date),
    };
  }

  factory GroupExpense.fromMap(Map<String, dynamic> map, String docId) {
    DateTime parsedDate = DateTime.now();
    final dateVal = map['date'];
    if (dateVal is Timestamp) {
      parsedDate = dateVal.toDate();
    } else if (dateVal is String) {
      parsedDate = DateTime.tryParse(dateVal) ?? DateTime.now();
    }

    final rawInvolved = map['involvedMembers'];
    List<String> parsedInvolved = [];
    if (rawInvolved is List) {
      parsedInvolved = rawInvolved.map((e) => e.toString()).toList();
    }

    final rawCustomSplit = map['customSplit'];
    final Map<String, double> parsedCustomSplit = {};
    if (rawCustomSplit is Map) {
      rawCustomSplit.forEach((k, v) {
        if (v is num) {
          parsedCustomSplit[k.toString()] = v.toDouble();
        }
      });
    }

    return GroupExpense(
      id: docId,
      groupId: map['groupId'] ?? '',
      description: map['description'] ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      payerName: map['payerName'] ?? '',
      involvedMembers: parsedInvolved,
      customSplit: parsedCustomSplit,
      date: parsedDate,
    );
  }
}

class GroupSettlement {
  final String fromPerson;
  final String toPerson;
  final double amount;

  GroupSettlement({
    required this.fromPerson,
    required this.toPerson,
    required this.amount,
  });
}
