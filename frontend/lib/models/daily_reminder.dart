
class DailyReminder {
  final String? id;
  final String title;
  final String description;
  final String time; // HH:MM format
  final bool isActive;
  final bool isAnnoying;
  final bool snoozeEnabled;
  final int snoozeIntervalMinutes;
  final int maxSnoozeCount;
  final int currentSnoozeCount;
  final String? lastTriggeredDate;
  final String? lastTriggeredTime;
  final String? lastCompletedDate;

  DailyReminder({
    this.id,
    required this.title,
    required this.description,
    required this.time,
    this.isActive = true,
    this.isAnnoying = false,
    this.snoozeEnabled = false,
    this.snoozeIntervalMinutes = 15,
    this.maxSnoozeCount = 3,
    this.currentSnoozeCount = 0,
    this.lastTriggeredDate,
    this.lastTriggeredTime,
    this.lastCompletedDate,
  });

  factory DailyReminder.fromMap(Map<String, dynamic> json, [String? id]) {
    return DailyReminder(
      id: id ?? json['id'],
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      time: json['time'] ?? '00:00',
      isActive: json['isActive'] == 1 || json['isActive'] == true,
      isAnnoying: json['isAnnoying'] == 1 || json['isAnnoying'] == true,
      snoozeEnabled: json['snoozeEnabled'] == 1 || json['snoozeEnabled'] == true,
      snoozeIntervalMinutes: json['snoozeIntervalMinutes'] ?? 15,
      maxSnoozeCount: json['maxSnoozeCount'] ?? 3,
      currentSnoozeCount: json['currentSnoozeCount'] ?? 0,
      lastTriggeredDate: json['lastTriggeredDate'],
      lastTriggeredTime: json['lastTriggeredTime'],
      lastCompletedDate: json['lastCompletedDate'],
    );
  }

  factory DailyReminder.fromJson(Map<String, dynamic> json, [String? id]) => 
      DailyReminder.fromMap(json, id);

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'time': time,
      'isActive': isActive,
      'isAnnoying': isAnnoying,
      'snoozeEnabled': snoozeEnabled,
      'snoozeIntervalMinutes': snoozeIntervalMinutes,
      'maxSnoozeCount': maxSnoozeCount,
      'currentSnoozeCount': currentSnoozeCount,
      'lastTriggeredDate': lastTriggeredDate,
      'lastTriggeredTime': lastTriggeredTime,
      'lastCompletedDate': lastCompletedDate,
    };
  }

  DailyReminder copyWith({
    String? id,
    String? title,
    String? description,
    String? time,
    bool? isActive,
    bool? isAnnoying,
    bool? snoozeEnabled,
    int? snoozeIntervalMinutes,
    int? maxSnoozeCount,
    int? currentSnoozeCount,
    String? lastTriggeredDate,
    String? lastTriggeredTime,
    String? lastCompletedDate,
  }) {
    return DailyReminder(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      time: time ?? this.time,
      isActive: isActive ?? this.isActive,
      isAnnoying: isAnnoying ?? this.isAnnoying,
      snoozeEnabled: snoozeEnabled ?? this.snoozeEnabled,
      snoozeIntervalMinutes: snoozeIntervalMinutes ?? this.snoozeIntervalMinutes,
      maxSnoozeCount: maxSnoozeCount ?? this.maxSnoozeCount,
      currentSnoozeCount: currentSnoozeCount ?? this.currentSnoozeCount,
      lastTriggeredDate: lastTriggeredDate ?? this.lastTriggeredDate,
      lastTriggeredTime: lastTriggeredTime ?? this.lastTriggeredTime,
      lastCompletedDate: lastCompletedDate ?? this.lastCompletedDate,
    );
  }

  // To map
  Map<String, dynamic> toMap() => toJson();
}
