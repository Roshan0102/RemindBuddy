class Note {
  final int? id;
  final String title;
  final String content;
  final String date;
  final bool isLocked;

  final String? remoteId;
  final bool isSynced;
  final String? updatedAt;

  Note({
    this.id,
    required this.title,
    required this.content,
    required this.date,
    this.isLocked = false,
    this.remoteId,
    this.isSynced = false,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'date': date,
      'isLocked': isLocked ? 1 : 0,
      'remoteId': remoteId,
      'isSynced': isSynced ? 1 : 0,
      'updatedAt': updatedAt ?? DateTime.now().toIso8601String(),
    };
  }

  factory Note.fromMap(Map<String, dynamic> map) {
    return Note(
      id: map['id'],
      title: map['title'],
      content: map['content'],
      date: map['date'],
      isLocked: map['isLocked'] == 1,
      remoteId: map['remoteId'],
      isSynced: map['isSynced'] == 1,
      updatedAt: map['updatedAt'],
    );
  }
}
