import 'package:cloud_firestore/cloud_firestore.dart';

class RecurringBill {
  final String id;
  final String title;
  final double amount;
  final String category;
  final DateTime dueDate;
  final DateTime? startDate;
  final String frequency; // 'monthly', 'yearly', 'weekly', etc.
  final List<String> notifications; // List of notification rules e.g. ["On the day at 9 AM"]
  final String? accountId;
  final bool isActive;
  final String notes;

  RecurringBill({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.dueDate,
    this.startDate,
    required this.frequency,
    this.notifications = const ['On the day at 9 AM'],
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
      'startDate': startDate != null ? Timestamp.fromDate(startDate!) : null,
      'frequency': frequency,
      'notifications': notifications,
      'accountId': accountId,
      'isActive': isActive,
      'notes': notes,
    };
  }

  factory RecurringBill.fromMap(Map<String, dynamic> map, String docId) {
    DateTime parsedDueDate = DateTime.now();
    final dateVal = map['dueDate'];
    if (dateVal is Timestamp) {
      parsedDueDate = dateVal.toDate();
    } else if (dateVal is String) {
      parsedDueDate = DateTime.tryParse(dateVal) ?? DateTime.now();
    }

    DateTime? parsedStartDate;
    final startVal = map['startDate'];
    if (startVal is Timestamp) {
      parsedStartDate = startVal.toDate();
    } else if (startVal is String) {
      parsedStartDate = DateTime.tryParse(startVal);
    }

    return RecurringBill(
      id: docId,
      title: map['title'] ?? 'Bill',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      category: map['category'] ?? 'General',
      dueDate: parsedDueDate,
      startDate: parsedStartDate,
      frequency: map['frequency'] ?? 'monthly',
      notifications: map['notifications'] != null
          ? List<String>.from(map['notifications'])
          : ['On the day at 9 AM'],
      accountId: map['accountId'],
      isActive: map['isActive'] as bool? ?? true,
      notes: map['notes'] ?? '',
    );
  }
}
