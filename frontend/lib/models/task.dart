class Task {
  final int? id;
  final String title;
  final String description;
  final String date; // YYYY-MM-DD
  final String time; // HH:MM
  final String repeat; // none, daily, weekly, monthly
  final bool isAnnoying;

  final String? remoteId;
  final bool isSynced;
  final String? updatedAt;

  Task({
    this.id,
    required this.title,
    required this.description,
    required this.date,
    required this.time,
    this.repeat = 'none',
    this.isAnnoying = false,
    this.remoteId,
    this.isSynced = false,
    this.updatedAt,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      date: json['date'],
      time: json['time'],
      repeat: json['repeat'] ?? 'none',
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
      'date': date,
      'time': time,
      'repeat': repeat,
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
      'date': date,
      'time': time,
      'repeat': repeat,
      'isAnnoying': isAnnoying ? 1 : 0,
      'remoteId': remoteId,
      'isSynced': isSynced ? 1 : 0,
      'updatedAt': updatedAt ?? DateTime.now().toIso8601String(),
    };
  }
}
