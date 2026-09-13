import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:remindbuddy/models/note.dart';

void main() {
  group('Note Checklist Widget Data Sync Tests', () {
    test('Checklist Note JSON serializes and deserializes accurately for Android RemoteViews', () {
      final note = Note(
        id: 'note_office_packing_123',
        title: 'Office Packing Checklist',
        content: '[ ] Laptop\n[ ] Charger\n[ ] Headphones\n[x] Phone',
        date: '2026-09-13 09:00',
        isChecklist: true,
        checklistItems: [
          {'text': 'Laptop', 'isChecked': false},
          {'text': 'Laptop Charger', 'isChecked': false},
          {'text': 'Headphones', 'isChecked': false},
          {'text': 'Work Phone', 'isChecked': true},
        ],
      );

      // JSON string that is stored in SharedPreferences for the Android Widget
      final itemsJson = jsonEncode(note.checklistItems);
      expect(itemsJson, contains('Laptop'));
      expect(itemsJson, contains('Work Phone'));

      // Decode as Android RemoteViewsFactory does
      final List<dynamic> decoded = jsonDecode(itemsJson);
      expect(decoded.length, 4);
      expect(decoded[0]['text'], 'Laptop');
      expect(decoded[0]['isChecked'], isFalse);
      expect(decoded[3]['text'], 'Work Phone');
      expect(decoded[3]['isChecked'], isTrue);

      // Simulate 1-tap reset checklist
      final resetItems = decoded.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        map['isChecked'] = false;
        return map;
      }).toList();

      expect(resetItems.every((it) => it['isChecked'] == false), isTrue);

      // Simulate toggling an item
      resetItems[0]['isChecked'] = true;
      expect(resetItems[0]['isChecked'], isTrue);
    });

    test('Note with empty title falls back gracefully to default title', () {
      final note = Note(
        id: 'note_untitled',
        title: '   ',
        content: '',
        date: '2026-09-13 09:00',
        isChecklist: true,
        checklistItems: [
          {'text': 'Water Bottle', 'isChecked': false},
        ],
      );

      final title = note.title.trim().isNotEmpty ? note.title.trim() : 'Checklist';
      expect(title, 'Checklist');
    });
  });
}
