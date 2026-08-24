import 'package:cloud_firestore/cloud_firestore.dart';

class GroupEvent {
  final String id;
  final String title;
  final List<String> members;
  final DateTime createdAt;
  final bool isArchived;

  GroupEvent({
    required this.id,
    required this.title,
    required this.members,
    required this.createdAt,
    this.isArchived = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'members': members,
      'createdAt': Timestamp.fromDate(createdAt),
      'isArchived': isArchived,
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
  final DateTime date;

  GroupExpense({
    required this.id,
    required this.groupId,
    required this.description,
    required this.amount,
    required this.payerName,
    required this.involvedMembers,
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

    return GroupExpense(
      id: docId,
      groupId: map['groupId'] ?? '',
      description: map['description'] ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      payerName: map['payerName'] ?? '',
      involvedMembers: parsedInvolved,
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
