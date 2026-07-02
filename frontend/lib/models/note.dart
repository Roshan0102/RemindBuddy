class Note {
  final String? id; // Changed to String for Firestore document IDs
  final String title;
  final String content;
  final String date;
  final bool isLocked;
  final String? ownerUid;
  final List<String> sharedWith;

  Note({
    this.id,
    required this.title,
    required this.content,
    required this.date,
    this.isLocked = false,
    this.ownerUid,
    this.sharedWith = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'content': content,
      'date': date,
      'isLocked': isLocked,
      'ownerUid': ownerUid,
      'sharedWith': sharedWith,
    };
  }

  factory Note.fromMap(Map<String, dynamic> map, String docId, {String? ownerUid}) {
    return Note(
      id: docId,
      title: map['title'] ?? '',
      content: map['content'] ?? '',
      date: map['date'] ?? '',
      isLocked: map['isLocked'] == true,
      ownerUid: ownerUid ?? map['ownerUid'],
      sharedWith: List<String>.from(map['sharedWith'] ?? []),
    );
  }
}
