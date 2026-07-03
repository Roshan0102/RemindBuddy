import 'package:cloud_firestore/cloud_firestore.dart';

class CalendarReminder {
  final String? id;
  final String title;
  final String description;
  final String date; // YYYY-MM-DD
  final String time; // HH:mm
  final String status; // pending, scheduled, completed, expired, error
  final Timestamp? expireAt;
  final bool isRecurring;
  final int recurrenceValue;
  final String recurrenceUnit; // 'days', 'weeks', 'months', etc.
  final int? remainingOccurrences; // null means infinite
  final String? scheduledByUid;
  final String? scheduledByUsername;
  final bool snoozeEnabled;
  final int snoozeIntervalMinutes;
  final int maxSnoozeCount;
  final int currentSnoozeCount;

  CalendarReminder({
    this.id,
    required this.title,
    required this.description,
    required this.date,
    required this.time,
    this.status = 'pending',
    this.expireAt,
    this.isRecurring = false,
    this.recurrenceValue = 1,
    this.recurrenceUnit = 'days',
    this.remainingOccurrences,
    this.scheduledByUid,
    this.scheduledByUsername,
    this.snoozeEnabled = false,
    this.snoozeIntervalMinutes = 15,
    this.maxSnoozeCount = 3,
    this.currentSnoozeCount = 0,
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
      isRecurring: json['isRecurring'] ?? false,
      recurrenceValue: json['recurrenceValue'] ?? 1,
      recurrenceUnit: json['recurrenceUnit'] ?? 'days',
      remainingOccurrences: json['remainingOccurrences'] as int?,
      scheduledByUid: json['scheduledByUid'],
      scheduledByUsername: json['scheduledByUsername'],
      snoozeEnabled: json['snoozeEnabled'] ?? false,
      snoozeIntervalMinutes: json['snoozeIntervalMinutes'] ?? 15,
      maxSnoozeCount: json['maxSnoozeCount'] ?? 3,
      currentSnoozeCount: json['currentSnoozeCount'] ?? 0,
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
      'isRecurring': isRecurring,
      'recurrenceValue': recurrenceValue,
      'recurrenceUnit': recurrenceUnit,
      'remainingOccurrences': remainingOccurrences,
      'snoozeEnabled': snoozeEnabled,
      'snoozeIntervalMinutes': snoozeIntervalMinutes,
      'maxSnoozeCount': maxSnoozeCount,
      'currentSnoozeCount': currentSnoozeCount,
      if (scheduledByUid != null) 'scheduledByUid': scheduledByUid,
      if (scheduledByUsername != null) 'scheduledByUsername': scheduledByUsername,
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
    bool? isRecurring,
    int? recurrenceValue,
    String? recurrenceUnit,
    int? remainingOccurrences,
    String? scheduledByUid,
    String? scheduledByUsername,
    bool? snoozeEnabled,
    int? snoozeIntervalMinutes,
    int? maxSnoozeCount,
    int? currentSnoozeCount,
  }) {
    return CalendarReminder(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      date: date ?? this.date,
      time: time ?? this.time,
      status: status ?? this.status,
      expireAt: expireAt ?? this.expireAt,
      isRecurring: isRecurring ?? this.isRecurring,
      recurrenceValue: recurrenceValue ?? this.recurrenceValue,
      recurrenceUnit: recurrenceUnit ?? this.recurrenceUnit,
      remainingOccurrences: remainingOccurrences ?? this.remainingOccurrences,
      scheduledByUid: scheduledByUid ?? this.scheduledByUid,
      scheduledByUsername: scheduledByUsername ?? this.scheduledByUsername,
      snoozeEnabled: snoozeEnabled ?? this.snoozeEnabled,
      snoozeIntervalMinutes: snoozeIntervalMinutes ?? this.snoozeIntervalMinutes,
      maxSnoozeCount: maxSnoozeCount ?? this.maxSnoozeCount,
      currentSnoozeCount: currentSnoozeCount ?? this.currentSnoozeCount,
    );
  }
}
