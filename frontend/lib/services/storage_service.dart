import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/task.dart';
import '../models/note.dart';
import '../models/daily_reminder.dart';
import '../models/gold_price.dart';


class StorageService {
  static final StorageService _instance = StorageService._internal();
  static const String _authTokenKey = 'auth_token';
  static const String _userKey = 'user_data';

  factory StorageService() {
    return _instance;
  }

  StorageService._internal();


  // Task Methods (Migrated to Firebase)
  Future<String> insertTask(Task task) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return '';
    
    final docRef = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('tasks')
        .add(task.toMap());
    
    return docRef.id;
  }

  Future<List<Task>> getTasks() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('tasks')
        .get();
        
    return snap.docs.map((doc) => Task.fromJson(doc.data(), doc.id)).toList();
  }

  Future<List<Task>> getTasksForDate(String date) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('tasks')
        .where('date', isEqualTo: date)
        .get();
        
    return snap.docs.map((doc) => Task.fromJson(doc.data(), doc.id)).toList();
  }

  Stream<List<Task>> getTasksForDateStream(String date) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();
    
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('tasks')
        .where('date', isEqualTo: date)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => Task.fromJson(doc.data(), doc.id)).toList());
  }

  Future<void> updateTask(Task task) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || task.id == null) return;
    
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('tasks')
        .doc(task.id)
        .update(task.toMap());
  }

  Future<void> deleteTask(String id) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('tasks')
        .doc(id)
        .delete();
  }

  Future<void> clearOldTasks(String today) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('tasks')
        .where('date', isLessThan: today)
        .get();
        
    for (var doc in snap.docs) {
      await doc.reference.delete();
    }
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
        .orderBy('time', descending: false)
        .get();
        
    return snap.docs.map((d) => DailyReminder.fromJson(d.data(), d.id)).toList();
  }

  Stream<List<DailyReminder>> getDailyRemindersStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();
    
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('daily_reminders')
        .orderBy('time', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map((d) => DailyReminder.fromJson(d.data(), d.id)).toList());
  }

  Future<List<DailyReminder>> getActiveDailyReminders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('daily_reminders')
        .where('isActive', isEqualTo: true)
        .orderBy('time', descending: false)
        .get();
        
    return snap.docs.map((d) => DailyReminder.fromJson(d.data(), d.id)).toList();
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


  // Checklist Methods (Migrated to Firebase)
  Future<String> createChecklist(String title, int iconCode, int color) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return '';
    
    final docRef = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('checklists')
        .add({
      'title': title,
      'iconCode': iconCode,
      'color': color,
      'createdAt': DateTime.now().toIso8601String(),
    });
    return docRef.id;
  }

  Future<List<Map<String, dynamic>>> getChecklists() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('checklists')
        .orderBy('createdAt', descending: false)
        .get();
        
    return snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return data;
    }).toList();
  }

  Stream<List<Map<String, dynamic>>> getChecklistsStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();
    
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('checklists')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
          final data = d.data();
          data['id'] = d.id;
          return data;
        }).toList());
  }

  Future<void> deleteChecklist(String id) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('checklists')
        .doc(id)
        .delete();
        
    // Delete all items under it
    final items = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('checklists')
        .doc(id)
        .collection('items')
        .get();
    for (var doc in items.docs) {
      await doc.reference.delete();
    }
  }

  Future<String> addChecklistItem(String checklistId, String text) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return '';
    
    final docRef = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('checklists')
        .doc(checklistId)
        .collection('items')
        .add({
      'text': text,
      'isChecked': 0,
      'createdAt': DateTime.now().toIso8601String(),
    });
    return docRef.id;
  }

  Future<List<Map<String, dynamic>>> getChecklistItems(String checklistId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('checklists')
        .doc(checklistId)
        .collection('items')
        .orderBy('createdAt', descending: false)
        .get();
        
    return snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return data;
    }).toList();
  }

  Stream<List<Map<String, dynamic>>> getChecklistItemsStream(String checklistId) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();
    
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('checklists')
        .doc(checklistId)
        .collection('items')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
          final data = d.data();
          data['id'] = d.id;
          return data;
        }).toList());
  }

  Future<void> toggleChecklistItem(String checklistId, String id, bool isChecked) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('checklists')
        .doc(checklistId)
        .collection('items')
        .doc(id)
        .update({
      'isChecked': isChecked ? 1 : 0,
    });
  }

  Future<void> deleteChecklistItem(String checklistId, String id) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('checklists')
        .doc(checklistId)
        .collection('items')
        .doc(id)
        .delete();
  }

  Future<void> resetChecklistItems(String checklistId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final items = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('checklists')
        .doc(checklistId)
        .collection('items')
        .get();
        
    for (var doc in items.docs) {
      await doc.reference.update({'isChecked': 0});
    }
  }

  // Gold Price Methods (Migrated to Firebase)
  Future<void> saveGoldPrice(GoldPrice price) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    // Calculate price change if not provided
    double change = price.priceChange;
    if (change == 0.0) {
      final prevPrice = await getPreviousGoldPrice(dateToExclude: price.date);
      if (prevPrice != null) {
        change = price.price - prevPrice;
      }
    }

    final data = price.toJson();
    data['priceChange'] = change;

    // Use date as document ID to ensure one entry per date
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('gold_prices')
        .doc(price.date)
        .set(data, SetOptions(merge: true));
  }

  Future<List<GoldPrice>> getGoldPriceHistory({int limit = 20}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('gold_prices')
        .orderBy('date', descending: true)
        .limit(limit)
        .get();
        
    return snap.docs.map((d) => GoldPrice.fromJson(d.data(), d.id)).toList();
  }

  Future<double?> getPreviousGoldPrice({String? dateToExclude}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    
    if (dateToExclude != null) {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('gold_prices')
          .where('date', isLessThan: dateToExclude)
          .orderBy('date', descending: true)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      return (snap.docs.first.data()['price'] as num).toDouble();
    } else {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('gold_prices')
          .orderBy('date', descending: true)
          .limit(2)
          .get();
      if (snap.docs.length < 2) return null;
      return (snap.docs[1].data()['price'] as num).toDouble();
    }
  }

  Future<List<GoldPrice>> getGoldPrices({int limit = 10}) async {
    return getGoldPriceHistory(limit: limit);
  }

  Future<GoldPrice?> getLatestGoldPrice() async {
    final prices = await getGoldPriceHistory(limit: 1);
    if (prices.isEmpty) return null;
    return prices.first;
  }

  Future<void> clearGoldPrices() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final batch = FirebaseFirestore.instance.batch();
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('gold_prices')
        .get();
        
    for (var doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  // Shift Methods
  Future<void> saveShiftRoster(String employeeName, String month, List<Map<String, dynamic>> shifts, {String? rosterMonth, String? rawJson, bool skipSyncFlag = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final effectiveRosterMonth = rosterMonth ?? (shifts.isNotEmpty ? shifts[0]['date'].toString().substring(0, 7) : month);
    
    final batch = FirebaseFirestore.instance.batch();
    
    // 1. Metadata at the Month level
    final monthRef = FirebaseFirestore.instance
        .collection('users').doc(user.uid)
        .collection('shifts').doc(effectiveRosterMonth);
        
    batch.set(monthRef, {
      'employee_name': employeeName,
      'month': month,
      'roster_month': effectiveRosterMonth,
      'raw_json': rawJson,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    
    // 2. Individual days in a sub-collection
    for (var shift in shifts) {
      final date = shift['date'] as String;
      final shiftRef = monthRef.collection('daily_shifts').doc(date);
        
      final shiftData = Map<String, dynamic>.from(shift);
      shiftData['roster_month'] = effectiveRosterMonth;
      batch.set(shiftRef, shiftData, SetOptions(merge: true));
    }
    
    await batch.commit();
    print('✅ Saved ${shifts.length} shifts to nested structure: shifts/$effectiveRosterMonth/daily_shifts');
  }

  Future<Map<String, String>?> getShiftMetadata({String? rosterMonth}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    
    if (rosterMonth != null) {
      final doc = await FirebaseFirestore.instance
        .collection('users').doc(user.uid)
        .collection('shifts').doc(rosterMonth).get();
      if (!doc.exists) return null;
      final data = doc.data()!;
      return {
        'employee_name': data['employee_name'] as String,
        'month': data['month'] as String,
        'roster_month': data['roster_month'] as String? ?? data['month'] as String,
      };
    } else {
      final snap = await FirebaseFirestore.instance
        .collection('users').doc(user.uid)
        .collection('shifts')
        .orderBy('roster_month', descending: true)
        .limit(1).get();
      if (snap.docs.isEmpty) return null;
      final data = snap.docs.first.data();
      return {
        'employee_name': data['employee_name'] as String,
        'month': data['month'] as String,
        'roster_month': data['roster_month'] as String? ?? data['month'] as String,
      };
    }
  }

  Future<List<Map<String, dynamic>>> getAllShifts({String? rosterMonth}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    
    if (rosterMonth == null) return [];

    final snap = await FirebaseFirestore.instance
        .collection('users').doc(user.uid)
        .collection('shifts')
        .doc(rosterMonth)
        .collection('daily_shifts')
        .get();
        
    final shifts = snap.docs.map((d) => d.data() as Map<String, dynamic>).toList();
    
    // Sort in memory to avoid needing a composite index for where + orderBy
    shifts.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
    
    return shifts;
  }

  Future<Map<String, dynamic>?> getShiftForDate(String date) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    
    final month = date.substring(0, 7);
    final doc = await FirebaseFirestore.instance
        .collection('users').doc(user.uid)
        .collection('shifts').doc(month)
        .collection('daily_shifts').doc(date).get();
        
    if (!doc.exists) return null;
    return doc.data() as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getUpcomingShifts(int days) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    
    final todayStr = DateTime.now().toIso8601String().split('T')[0];
    final endDateStr = DateTime.now().add(Duration(days: days)).toIso8601String().split('T')[0];
    
    final snap = await FirebaseFirestore.instance
        .collection('users').doc(user.uid)
        .collection('shifts')
        .where('date', isGreaterThanOrEqualTo: todayStr)
        .where('date', isLessThanOrEqualTo: endDateStr)
        .orderBy('date', descending: false).get();
        
    return snap.docs.map((d) => d.data()).toList();
  }

  Future<Map<String, int>> getShiftStatistics(String month, {String? rosterMonth}) async {
    final shifts = await getAllShifts(rosterMonth: rosterMonth);
    
    int morningCount = 0;
    int afternoonCount = 0;
    int nightCount = 0;
    int weekOffCount = 0;
    
    for (var shift in shifts) {
      final d = shift['date'] as String;
      if (!d.startsWith(month)) continue;
      
      switch (shift['shift_type']) {
        case 'morning': morningCount++; break;
        case 'afternoon': afternoonCount++; break;
        case 'night': nightCount++; break;
        case 'week_off': weekOffCount++; break;
      }
    }
    
    return {
      'morning': morningCount,
      'afternoon': afternoonCount,
      'night': nightCount,
      'week_off': weekOffCount,
      'total_working': morningCount + afternoonCount + nightCount,
    };
  }

  Future<List<Map<String, dynamic>>> getMonthlyRosters() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    
    final snap = await FirebaseFirestore.instance
      .collection('users').doc(user.uid)
      .collection('shift_metadata').get();
      
    return snap.docs.map((d) => d.data()).toList();
  }

  Future<void> clearAllShifts({String? rosterMonth}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    if (rosterMonth != null) {
      // Delete specific month
      final monthRef = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('shifts').doc(rosterMonth);
      
      // Delete sub-collection
      final daysSnap = await monthRef.collection('daily_shifts').get();
      final batch = FirebaseFirestore.instance.batch();
      for (var d in daysSnap.docs) { batch.delete(d.reference); }
      batch.delete(monthRef); // Delete the month doc itself
      await batch.commit();
    } else {
      // Clear EVERYTHING in shifts
      final monthsSnap = await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('shifts').get();
      for (var monthDoc in monthsSnap.docs) {
        final daysSnap = await monthDoc.reference.collection('daily_shifts').get();
        final batch = FirebaseFirestore.instance.batch();
        for (var d in daysSnap.docs) { batch.delete(d.reference); }
        batch.delete(monthDoc.reference);
        await batch.commit();
      }
    }
  }
  
  // Get list of available roster months
  Future<List<String>> getAvailableRosterMonths() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    
    final snap = await FirebaseFirestore.instance
      .collection('users').doc(user.uid)
      .collection('shifts')
      .orderBy(FieldPath.documentId, descending: true).get();
      
    return snap.docs.map((d) => d.id).toList();
  }

  // --- Auth & Sync Helpers ---

  Future<void> saveAuthToken(String token, String userData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_authTokenKey, token);
    await prefs.setString(_userKey, userData);
  }

  Future<String?> getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_authTokenKey);
  }

  Future<bool> isLoggedIn() async {
    return FirebaseAuth.instance.currentUser != null;
  }

  Future<void> logoutAndClearData() async {
    // 1. Firebase Logout
    await FirebaseAuth.instance.signOut();

    // 2. Clear SharedPreferences
    // 2. Clear SharedPreferences completely to wipe all local settings/data
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    print('🔒 User logged out, local preferences cleared, and session closed.');
  }
}
