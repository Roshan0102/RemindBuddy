class Task {
  final int? id;
  final String title;
  final String description;
  final String date; // YYYY-MM-DD
  final String time; // HH:MM
  final String repeat; // none, daily, weekly, monthly

  Task({
    this.id,
    required this.title,
    required this.description,
    required this.date,
    required this.time,
    this.repeat = 'none',
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      date: json['date'],
      time: json['time'],
      repeat: json['repeat'] ?? 'none',
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
    };
  }
}
