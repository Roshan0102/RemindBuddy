import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationHistory {
  final String id;
  final String title;
  final String body;
  final DateTime timestamp;
  final String type;

  NotificationHistory({
    required this.id,
    required this.title,
    required this.body,
    required this.timestamp,
    required this.type,
  });

  factory NotificationHistory.fromMap(Map<String, dynamic> map, String docId) {
    final Timestamp ts = map['timestamp'] as Timestamp? ?? Timestamp.now();
    return NotificationHistory(
      id: docId,
      title: map['title'] ?? '',
      body: map['body'] ?? '',
      timestamp: ts.toDate(),
      type: map['type'] ?? 'GENERAL',
    );
  }
}
