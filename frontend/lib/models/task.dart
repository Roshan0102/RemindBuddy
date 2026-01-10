class Task {
  final int? id;
  final String title;
  final String description;
  final String date; // YYYY-MM-DD
  final String time; // HH:MM
  final String repeat; // none, daily, weekly, monthly
  final bool isAnnoying;

  Task({
    this.id,
    required this.title,
    required this.description,
    required this.date,
    required this.time,
    this.repeat = 'none',
    this.isAnnoying = false,
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
    };
  }
}
