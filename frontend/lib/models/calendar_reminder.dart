
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

  factory CalendarReminder.fromMap(Map<String, dynamic> json, String docId) {
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

  // Alias for backward compatibility if any
  factory CalendarReminder.fromFirestore(Map<String, dynamic> json, String docId) => 
      CalendarReminder.fromMap(json, docId);

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'date': date,
      'time': time,
      'status': status,
    };
  }

  CalendarReminder copyWith({
    String? id,
    String? title,
    String? description,
    String? date,
    String? time,
    String? status,
    Timestamp? expireAt,
  }) {
    return CalendarReminder(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      date: date ?? this.date,
      time: time ?? this.time,
      status: status ?? this.status,
      expireAt: expireAt ?? this.expireAt,
    );
  }
}
