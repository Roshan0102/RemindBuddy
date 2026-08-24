import 'package:cloud_firestore/cloud_firestore.dart';

class DebtRecord {
  final String id;
  final String personName;
  final String type; // 'lent' (they owe me) or 'borrowed' (I owe them)
  final double amount;
  final String note;
  final DateTime date;
  final bool isSettled;
  final String? accountId;

  DebtRecord({
    required this.id,
    required this.personName,
    required this.type,
    required this.amount,
    required this.note,
    required this.date,
    this.isSettled = false,
    this.accountId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'personName': personName,
      'type': type,
      'amount': amount,
      'note': note,
      'date': Timestamp.fromDate(date),
      'isSettled': isSettled,
      'accountId': accountId,
    };
  }

  factory DebtRecord.fromMap(Map<String, dynamic> map, String docId) {
    DateTime parsedDate = DateTime.now();
    final dateVal = map['date'];
    if (dateVal is Timestamp) {
      parsedDate = dateVal.toDate();
    } else if (dateVal is String) {
      parsedDate = DateTime.tryParse(dateVal) ?? DateTime.now();
    }

    return DebtRecord(
      id: docId,
      personName: map['personName'] ?? 'Person',
      type: map['type'] ?? 'lent',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      note: map['note'] ?? '',
      date: parsedDate,
      isSettled: map['isSettled'] as bool? ?? false,
      accountId: map['accountId'],
    );
  }
}
