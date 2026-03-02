class Note {
  final String? id; // Changed to String for Firestore document IDs
  final String title;
  final String content;
  final String date;
  final bool isLocked;

  Note({
    this.id,
    required this.title,
    required this.content,
    required this.date,
    this.isLocked = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'content': content,
      'date': date,
      'isLocked': isLocked,
    };
  }

  factory Note.fromMap(Map<String, dynamic> map, String docId) {
    return Note(
      id: docId,
      title: map['title'] ?? '',
      content: map['content'] ?? '',
      date: map['date'] ?? '',
      isLocked: map['isLocked'] == true,
    );
  }
}
