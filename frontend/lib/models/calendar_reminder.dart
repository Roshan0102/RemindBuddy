
import 'package:cloud_firestore/cloud_firestore.dart';

class CalendarReminder {
  final String? id;
  final String title;
  final String description;
  final String date; // YYYY-MM-DD
  final String time; // HH:mm
  final String status; // pending, scheduled, completed, expired, error
  final Timestamp? expireAt;

  CalendarReminder({
    this.id,
    required this.title,
    required this.description,
    required this.date,
    required this.time,
    this.status = 'pending',
    this.expireAt,
  });

  factory CalendarReminder.fromFirestore(Map<String, dynamic> json, String docId) {
    return CalendarReminder(
      id: docId,
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      date: json['date'] ?? '',
      time: json['time'] ?? '',
      status: json['status'] ?? 'pending',
      expireAt: json['expireAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'date': date,
      'time': time,
      'status': status,
      // expireAt is managed by backend usually, but can be set here if needed
    };
  }
}
