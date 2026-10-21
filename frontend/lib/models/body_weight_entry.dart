import 'package:cloud_firestore/cloud_firestore.dart';

/// Tracks daily or weekly bodyweight check-ins
class BodyWeightEntry {
  final String id;
  final String userId;
  final double weightKg;
  final DateTime date;
  final String? note;

  const BodyWeightEntry({
    required this.id,
    required this.userId,
    required this.weightKg,
    required this.date,
    this.note,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'weightKg': weightKg,
      'date': Timestamp.fromDate(date),
      if (note != null) 'note': note,
    };
  }

  factory BodyWeightEntry.fromMap(Map<String, dynamic> map, {String? docId}) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return BodyWeightEntry(
      id: docId ?? map['id']?.toString() ?? '',
      userId: map['userId']?.toString() ?? '',
      weightKg: (map['weightKg'] as num?)?.toDouble() ?? 0.0,
      date: parseDate(map['date']),
      note: map['note']?.toString(),
    );
  }
}
