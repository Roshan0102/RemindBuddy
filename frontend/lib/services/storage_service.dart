
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/note.dart';
import '../models/daily_reminder.dart';
import '../models/gold_price.dart';
import '../models/calendar_reminder.dart';


class StorageService {
  static final StorageService _instance = StorageService._internal();

  factory StorageService() {
    return _instance;
  }

  StorageService._internal();


  // Calendar Reminder Methods (New Cloud Tasks backed reminders)
  Future<String> insertCalendarReminder(String title, String description, String date, String time) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return '';
    
    final docRef = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('calendar_reminders')
        .add({
      'title': title,
      'description': description,
      'date': date,
      'time': time,
      'status': 'pending', 
      'createdAt': FieldValue.serverTimestamp(),
    });
    
    return docRef.id;
  }

  Stream<List<CalendarReminder>> getCalendarRemindersStream(String date) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();
    
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('calendar_reminders')
        .where('date', isEqualTo: date)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
          return CalendarReminder.fromMap(doc.data(), doc.id);
        }).toList());
  }

  Future<void> deleteCalendarReminder(String id) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('calendar_reminders')
        .doc(id)
        .delete();
  }

  // Note Methods (Firebase Firestore)
  Future<String> insertNote(Note note) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return '';
    
    final docRef = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notes')
        .add(note.toMap());
        
    return docRef.id;
  }

  Future<List<Note>> getNotes() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    
    final querySnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notes')
        .orderBy('date', descending: true)
        .get();
        
    return querySnapshot.docs
        .map((doc) => Note.fromMap(doc.data(), doc.id))
        .toList();
  }

  Stream<List<Note>> getNotesStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();
    
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notes')
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => Note.fromMap(doc.data(), doc.id)).toList());
  }

  Future<void> updateNote(Note note) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || note.id == null) return;
    
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notes')
        .doc(note.id)
        .update(note.toMap());
  }

  Future<void> deleteNote(String id) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notes')
        .doc(id)
        .delete();
  }

  // Daily Reminder Methods
  Future<String> insertDailyReminder(DailyReminder reminder) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return '';
    
    final docRef = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('daily_reminders')
        .add(reminder.toMap());
    
    return docRef.id;
  }

  Future<List<DailyReminder>> getDailyReminders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('daily_reminders')
        .get();
    
    return snap.docs.map((doc) => DailyReminder.fromMap(doc.data(), doc.id)).toList();
  }

  Stream<List<DailyReminder>> getDailyRemindersStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();
    
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('daily_reminders')
        .snapshots()
        .map((snap) => snap.docs.map((doc) => DailyReminder.fromMap(doc.data(), doc.id)).toList());
  }

  Future<void> updateDailyReminder(DailyReminder reminder) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || reminder.id == null) return;
    
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('daily_reminders')
        .doc(reminder.id)
        .update(reminder.toMap());
  }

  Future<void> deleteDailyReminder(String id) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('daily_reminders')
        .doc(id)
        .delete();
  }

  Future<void> toggleDailyReminderActive(String id, bool isActive) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('daily_reminders')
        .doc(id)
        .update({'isActive': isActive});
  }

  // Checklist Methods
  Future<List<Map<String, dynamic>>> getChecklists() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('checklists').orderBy('createdAt', descending: true).get();
    return snap.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
  }

  Stream<List<Map<String, dynamic>>> getChecklistsStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();
    return FirebaseFirestore.instance.collection('users').doc(user.uid).collection('checklists').orderBy('createdAt', descending: true).snapshots().map((snap) => snap.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList());
  }

  Future<void> createChecklist(String title, int iconCode, int colorValue) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('checklists').add({
      'title': title,
      'iconCode': iconCode,
      'colorValue': colorValue,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteChecklist(String id) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('checklists').doc(id).delete();
  }

  Future<void> addChecklistItem(String listId, String text) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('checklists').doc(listId).collection('items').add({
      'text': text,
      'isChecked': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> toggleChecklistItem(String listId, String itemId, bool isChecked) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('checklists').doc(listId).collection('items').doc(itemId).update({
      'isChecked': isChecked,
    });
  }

  Future<void> deleteChecklistItem(String listId, String itemId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('checklists').doc(listId).collection('items').doc(itemId).delete();
  }

  Future<void> resetChecklistItems(String listId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final items = await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('checklists').doc(listId).collection('items').get();
    final batch = FirebaseFirestore.instance.batch();
    for (var doc in items.docs) {
      batch.update(doc.reference, {'isChecked': false});
    }
    await batch.commit();
  }

  Stream<List<Map<String, dynamic>>> getChecklistItemsStream(String listId) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();
    return FirebaseFirestore.instance.collection('users').doc(user.uid).collection('checklists').doc(listId).collection('items').orderBy('createdAt', descending: false).snapshots().map((snap) => snap.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList());
  }


  // Shift Methods
  Future<Map<String, dynamic>?> getShiftMetadata({required String rosterMonth}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('shifts').doc(rosterMonth).get();
    return doc.exists ? doc.data() : null;
  }

  Future<List<Map<String, dynamic>>> getAllShifts({required String rosterMonth}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('shifts').doc(rosterMonth).collection('daily_shifts').orderBy('date').get();
    return snap.docs.map((doc) => doc.data()).toList();
  }

  Future<Map<String, int>> getShiftStatistics(String month, {required String rosterMonth}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return {'morning': 0, 'afternoon': 0, 'night': 0, 'week_off': 0, 'total_working': 0};
    
    final shifts = await getAllShifts(rosterMonth: rosterMonth);
    int m = 0, a = 0, n = 0, w = 0, tw = 0;
    for (var s in shifts) {
      final type = s['shift_type']?.toString().toLowerCase() ?? '';
      if (type == 'morning') m++;
      else if (type == 'afternoon') a++;
      else if (type == 'night') n++;
      else if (type == 'week_off') w++;
      
      if (type != 'week_off') tw++;
    }
    return {'morning': m, 'afternoon': a, 'night': n, 'week_off': w, 'total_working': tw};
  }

  Future<void> saveShiftRoster(String employeeName, String monthLabel, List<Map<String, dynamic>> shifts, {required String rosterMonth, required String rawJson}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final batch = FirebaseFirestore.instance.batch();
    final monthRef = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('shifts').doc(rosterMonth);
    
    batch.set(monthRef, {
      'employee_name': employeeName,
      'month_label': monthLabel,
      'last_updated': FieldValue.serverTimestamp(),
      'raw_json': rawJson,
    });

    final dailyShiftsRef = monthRef.collection('daily_shifts');
    for (var s in shifts) {
      batch.set(dailyShiftsRef.doc(s['date']), s);
    }
    await batch.commit();
  }

  Future<void> clearAllShifts({required String rosterMonth}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final monthRef = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('shifts').doc(rosterMonth);
    final dailyShifts = await monthRef.collection('daily_shifts').get();
    
    final batch = FirebaseFirestore.instance.batch();
    for (var doc in dailyShifts.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(monthRef);
    await batch.commit();
  }

  Future<Map<String, dynamic>?> getShiftForDate(String date) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final month = date.substring(0, 7);
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('shifts').doc(month).collection('daily_shifts').doc(date).get();
    return doc.exists ? doc.data() : null;
  }

  Stream<QuerySnapshot> getMonthlyShiftsStream(String month) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();
    return FirebaseFirestore.instance.collection('users').doc(user.uid).collection('shifts').doc(month).collection('daily_shifts').snapshots();
  }

  // Auth Methods
  Future<void> logoutAndClearData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
