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
    this.remoteId,
    this.isSynced = false,
    this.updatedAt,
  });

  final String? remoteId;
  final bool isSynced;
  final String? updatedAt;

  factory DailyReminder.fromJson(Map<String, dynamic> json) {
    return DailyReminder(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      time: json['time'],
      isActive: json['isActive'] == 1 || json['isActive'] == true,
      isAnnoying: json['isAnnoying'] == 1 || json['isAnnoying'] == true,
      remoteId: json['remoteId'],
      isSynced: json['isSynced'] == 1 || json['isSynced'] == true,
      updatedAt: json['updatedAt'],
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
      'remoteId': remoteId,
      'isSynced': isSynced,
      'updatedAt': updatedAt,
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
      'remoteId': remoteId,
      'isSynced': isSynced ? 1 : 0,
      'updatedAt': updatedAt ?? DateTime.now().toIso8601String(),
    };
  }
}
