import 'package:cloud_firestore/cloud_firestore.dart';

class RecurringBill {
  final String id;
  final String title;
  final double amount;
  final String category;
  final DateTime dueDate;
  final String frequency; // 'monthly', 'yearly', 'weekly'
  final String? accountId;
  final bool isActive;
  final String notes;

  RecurringBill({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.dueDate,
    required this.frequency,
    this.accountId,
    this.isActive = true,
    this.notes = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'amount': amount,
      'category': category,
      'dueDate': Timestamp.fromDate(dueDate),
      'frequency': frequency,
      'accountId': accountId,
      'isActive': isActive,
      'notes': notes,
    };
  }

  factory RecurringBill.fromMap(Map<String, dynamic> map, String docId) {
    DateTime parsedDate = DateTime.now();
    final dateVal = map['dueDate'];
    if (dateVal is Timestamp) {
      parsedDate = dateVal.toDate();
    } else if (dateVal is String) {
      parsedDate = DateTime.tryParse(dateVal) ?? DateTime.now();
    }

    return RecurringBill(
      id: docId,
      title: map['title'] ?? 'Bill',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      category: map['category'] ?? 'General',
      dueDate: parsedDate,
      frequency: map['frequency'] ?? 'monthly',
      accountId: map['accountId'],
      isActive: map['isActive'] as bool? ?? true,
      notes: map['notes'] ?? '',
    );
  }
}
