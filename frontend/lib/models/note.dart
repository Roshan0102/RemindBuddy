class Note {
  final int? id;
  final String title;
  final String content;
  final String date;
  final bool isLocked;

  Note({this.id, required this.title, required this.content, required this.date, this.isLocked = false});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'date': date,
      'isLocked': isLocked ? 1 : 0,
    };
  }

  factory Note.fromMap(Map<String, dynamic> map) {
    return Note(
      id: map['id'],
      title: map['title'],
      content: map['content'],
      date: map['date'],
      isLocked: map['isLocked'] == 1,
    );
  }
}
