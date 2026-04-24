
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/note.dart';
import '../models/daily_reminder.dart';
import '../models/gold_price.dart';
import '../models/calendar_reminder.dart';


class StorageService {
  static final StorageService _instance = StorageService._internal();
  static const String _authTokenKey = 'auth_token';
  static const String _userKey = 'user_data';

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
      'status': 'pending', // Status will be updated by onCalendarReminderCreated trigger
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

  // Note Methods (Migrated to Firebase Firestore)
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

  // Shift Methods
  Future<void> saveMonthlyShifts(String month, List<Map<String, dynamic>> shifts) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final batch = FirebaseFirestore.instance.batch();
    final monthRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('shifts')
        .doc(month);

    // Save metadata
    batch.set(monthRef, {'last_updated': FieldValue.serverTimestamp()}, SetOptions(merge: true));

    // Save each day's shift
    final dailyShiftsRef = monthRef.collection('daily_shifts');
    for (var s in shifts) {
      if (s['date'] != null) {
        batch.set(dailyShiftsRef.doc(s['date']), s, SetOptions(merge: true));
      }
    }
    
    await batch.commit();
  }

  Future<Map<String, dynamic>?> getShiftForDate(String date) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    
    final month = date.substring(0, 7); // YYYY-MM
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('shifts')
        .doc(month)
        .collection('daily_shifts')
        .doc(date)
        .get();
        
    return doc.exists ? doc.data() : null;
  }

  Stream<QuerySnapshot> getMonthlyShiftsStream(String month) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();
    
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('shifts')
        .doc(month)
        .collection('daily_shifts')
        .snapshots();
  }
}
