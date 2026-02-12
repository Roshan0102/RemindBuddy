class DailyReminder {
  final int? id;
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

  factory DailyReminder.fromJson(Map<String, dynamic> json) {
    return DailyReminder(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      time: json['time'],
      isActive: json['isActive'] == 1 || json['isActive'] == true,
      isAnnoying: json['isAnnoying'] == 1 || json['isAnnoying'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'time': time,
      'isActive': isActive,
      'isAnnoying': isAnnoying,
    };
  }

  // For SQLite
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'time': time,
      'isActive': isActive ? 1 : 0,
      'isAnnoying': isAnnoying ? 1 : 0,
    };
  }
}
