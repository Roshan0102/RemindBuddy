class DailyReminder {
  final String? id;
  final String title;
  final String description;
  final String time; // HH:MM format
  final bool isActive;
  final bool isAnnoying;

  DailyReminder({
    this.id,
    required this.title,
    required this.description,
    required this.time,
    this.isActive = true,
    this.isAnnoying = false,
  });

  factory DailyReminder.fromJson(Map<String, dynamic> json, [String? id]) {
    return DailyReminder(
      id: id ?? json['id'],
      title: json['title'],
      description: json['description'],
      time: json['time'],
      isActive: json['isActive'] == 1 || json['isActive'] == true,
      isAnnoying: json['isAnnoying'] == 1 || json['isAnnoying'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'time': time,
      'isActive': isActive,
      'isAnnoying': isAnnoying,
    };
  }

  DailyReminder copyWith({
    String? id,
    String? title,
    String? description,
    String? time,
    bool? isActive,
    bool? isAnnoying,
  }) {
    return DailyReminder(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      time: time ?? this.time,
      isActive: isActive ?? this.isActive,
      isAnnoying: isAnnoying ?? this.isAnnoying,
    );
  }

  // To map
  Map<String, dynamic> toMap() {
    return toJson();
  }
}
