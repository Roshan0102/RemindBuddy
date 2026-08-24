import 'package:cloud_firestore/cloud_firestore.dart';

class FinanceTransaction {
  final String id;
  final String accountId;
  final String type; // 'income' or 'expense'
  final double amount;
  final String category;
  final String note;
  final DateTime timestamp;

  FinanceTransaction({
    required this.id,
    required this.accountId,
    required this.type,
    required this.amount,
    required this.category,
    required this.note,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'accountId': accountId,
      'type': type,
      'amount': amount,
      'category': category,
      'note': note,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }

  factory FinanceTransaction.fromMap(Map<String, dynamic> map, String docId) {
    DateTime parsedDate = DateTime.now();
    final timeVal = map['timestamp'];
    if (timeVal is Timestamp) {
      parsedDate = timeVal.toDate();
    } else if (timeVal is String) {
      parsedDate = DateTime.tryParse(timeVal) ?? DateTime.now();
    }

    return FinanceTransaction(
      id: docId,
      accountId: map['accountId'] ?? '',
      type: map['type'] ?? 'expense',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      category: map['category'] ?? 'General',
      note: map['note'] ?? '',
      timestamp: parsedDate,
    );
  }
}
