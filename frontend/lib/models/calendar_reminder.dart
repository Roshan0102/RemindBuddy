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
  final String? scheduledForUid;
  final String? scheduledForUsername;
  final bool snoozeEnabled;
  final int snoozeIntervalMinutes;
  final int maxSnoozeCount;
  final int currentSnoozeCount;
  final String? taskId;
  final Timestamp? notifiedAt;
  final bool isLocationBased;
  final String? locationName;
  final double? latitude;
  final double? longitude;
  final double radiusMeters;
  final String triggerCondition; // 'enter' or 'exit'
  final bool isLocationTriggered;
  final String? savedPlaceId;

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
    this.scheduledForUid,
    this.scheduledForUsername,
    this.snoozeEnabled = false,
    this.snoozeIntervalMinutes = 15,
    this.maxSnoozeCount = 3,
    this.currentSnoozeCount = 0,
    this.taskId,
    this.notifiedAt,
    this.isLocationBased = false,
    this.locationName,
    this.latitude,
    this.longitude,
    this.radiusMeters = 50.0,
    this.triggerCondition = 'enter',
    this.isLocationTriggered = false,
    this.savedPlaceId,
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
      scheduledForUid: json['scheduledForUid'],
      scheduledForUsername: json['scheduledForUsername'],
      snoozeEnabled: json['snoozeEnabled'] ?? false,
      snoozeIntervalMinutes: json['snoozeIntervalMinutes'] ?? 15,
      maxSnoozeCount: json['maxSnoozeCount'] ?? 3,
      currentSnoozeCount: json['currentSnoozeCount'] ?? 0,
      taskId: json['taskId'] as String?,
      notifiedAt: json['notifiedAt'] as Timestamp?,
      isLocationBased: json['isLocationBased'] ?? false,
      locationName: json['locationName'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      radiusMeters: (json['radiusMeters'] as num?)?.toDouble() ?? 50.0,
      triggerCondition: json['triggerCondition'] as String? ?? 'enter',
      isLocationTriggered: json['isLocationTriggered'] ?? false,
      savedPlaceId: json['savedPlaceId'] as String?,
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
      if (scheduledForUid != null) 'scheduledForUid': scheduledForUid,
      if (scheduledForUsername != null) 'scheduledForUsername': scheduledForUsername,
      if (taskId != null) 'taskId': taskId,
      if (notifiedAt != null) 'notifiedAt': notifiedAt,
      'isLocationBased': isLocationBased,
      if (locationName != null) 'locationName': locationName,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      'radiusMeters': radiusMeters,
      'triggerCondition': triggerCondition,
      'isLocationTriggered': isLocationTriggered,
      if (savedPlaceId != null) 'savedPlaceId': savedPlaceId,
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
    String? scheduledForUid,
    String? scheduledForUsername,
    bool? snoozeEnabled,
    int? snoozeIntervalMinutes,
    int? maxSnoozeCount,
    int? currentSnoozeCount,
    String? taskId,
    Timestamp? notifiedAt,
    bool? isLocationBased,
    String? locationName,
    double? latitude,
    double? longitude,
    double? radiusMeters,
    String? triggerCondition,
    bool? isLocationTriggered,
    String? savedPlaceId,
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
      scheduledForUid: scheduledForUid ?? this.scheduledForUid,
      scheduledForUsername: scheduledForUsername ?? this.scheduledForUsername,
      snoozeEnabled: snoozeEnabled ?? this.snoozeEnabled,
      snoozeIntervalMinutes: snoozeIntervalMinutes ?? this.snoozeIntervalMinutes,
      maxSnoozeCount: maxSnoozeCount ?? this.maxSnoozeCount,
      currentSnoozeCount: currentSnoozeCount ?? this.currentSnoozeCount,
      taskId: taskId ?? this.taskId,
      notifiedAt: notifiedAt ?? this.notifiedAt,
      isLocationBased: isLocationBased ?? this.isLocationBased,
      locationName: locationName ?? this.locationName,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      triggerCondition: triggerCondition ?? this.triggerCondition,
      isLocationTriggered: isLocationTriggered ?? this.isLocationTriggered,
      savedPlaceId: savedPlaceId ?? this.savedPlaceId,
    );
  }
}

class GroupedCalendarReminder {
  final CalendarReminder primaryReminder;
  final List<CalendarReminder> originalReminders;
  final String title;
  final String description;
  final String date;
  final String time;
  final String status;
  final List<String> recipientUsernames;
  final Timestamp? notifiedAt;

  GroupedCalendarReminder({
    required this.primaryReminder,
    required this.originalReminders,
    required this.title,
    required this.description,
    required this.date,
    required this.time,
    required this.status,
    required this.recipientUsernames,
    this.notifiedAt,
  });

  static List<GroupedCalendarReminder> groupList(List<CalendarReminder> reminders) {
    if (reminders.isEmpty) return [];

    final Map<String, List<CalendarReminder>> groupMap = {};

    for (final r in reminders) {
      final key = '${r.title.trim().toLowerCase()}_${r.date}_${r.time}_${r.description.trim().toLowerCase()}';
      if (!groupMap.containsKey(key)) {
        groupMap[key] = [];
      }
      groupMap[key]!.add(r);
    }

    final List<GroupedCalendarReminder> result = [];

    for (final entry in groupMap.entries) {
      final list = entry.value;
      final first = list.first;

      final Set<String> recipientsSet = {};
      bool anyCompleted = false;
      bool allCompleted = true;
      Timestamp? groupNotifiedAt;

      for (final item in list) {
        if (item.scheduledForUsername != null && item.scheduledForUsername!.isNotEmpty) {
          recipientsSet.add('@${item.scheduledForUsername}');
        } else if (item.scheduledByUsername != null && item.scheduledByUsername!.isNotEmpty) {
          recipientsSet.add('from @${item.scheduledByUsername}');
        } else {
          recipientsSet.add('Myself');
        }

        if (item.status == 'completed') {
          anyCompleted = true;
        } else {
          allCompleted = false;
        }

        if (item.notifiedAt != null && groupNotifiedAt == null) {
          groupNotifiedAt = item.notifiedAt;
        }
      }

      String aggregateStatus = first.status;
      if (allCompleted || anyCompleted) {
        aggregateStatus = 'completed';
      }

      result.add(GroupedCalendarReminder(
        primaryReminder: first,
        originalReminders: list,
        title: first.title,
        description: first.description,
        date: first.date,
        time: first.time,
        status: aggregateStatus,
        recipientUsernames: recipientsSet.toList(),
        notifiedAt: groupNotifiedAt,
      ));
    }

    return result;
  }
}
