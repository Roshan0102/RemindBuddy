
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/note.dart';
import '../models/daily_reminder.dart';
import '../models/gold_price.dart';
import '../models/calendar_reminder.dart';
import '../models/notification_history.dart';


class StorageService {
  static final StorageService _instance = StorageService._internal();

  factory StorageService() {
    return _instance;
  }

  StorageService._internal();


  // Calendar Reminder Methods (New Cloud Tasks backed reminders)
  Future<String> insertCalendarReminder(
    String title, 
    String description, 
    String date, 
    String time, {
    bool isRecurring = false,
    int recurrenceValue = 1,
    String recurrenceUnit = 'days',
    int? remainingOccurrences,
    String? targetUid,
    String? targetUsername,
    bool snoozeEnabled = false,
    int snoozeIntervalMinutes = 15,
    int maxSnoozeCount = 3,
    int currentSnoozeCount = 0,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return '';
    
    final destinationUid = targetUid ?? user.uid;
    final Map<String, dynamic> data = {
      'title': title,
      'description': description,
      'date': date,
      'time': time,
      'status': 'pending', 
      'createdAt': FieldValue.serverTimestamp(),
      'isRecurring': isRecurring,
      'recurrenceValue': recurrenceValue,
      'recurrenceUnit': recurrenceUnit,
      'remainingOccurrences': remainingOccurrences,
      'snoozeEnabled': snoozeEnabled,
      'snoozeIntervalMinutes': snoozeIntervalMinutes,
      'maxSnoozeCount': maxSnoozeCount,
      'currentSnoozeCount': currentSnoozeCount,
    };

    if (destinationUid != user.uid) {
      data['scheduledByUid'] = user.uid;
      final myUsername = await getCurrentUsername();
      if (myUsername != null) {
        data['scheduledByUsername'] = myUsername;
      }
      
      final targetDocRef = FirebaseFirestore.instance
          .collection('users')
          .doc(destinationUid)
          .collection('calendar_reminders')
          .doc();

      final myDocRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('calendar_reminders')
          .doc();

      data['pairedDocId'] = myDocRef.id;
      data['pairedUid'] = user.uid;

      final Map<String, dynamic> myCopy = Map<String, dynamic>.from(data);
      myCopy['scheduledForUid'] = destinationUid;
      if (targetUsername != null) {
        myCopy['scheduledForUsername'] = targetUsername;
      }
      myCopy['pairedDocId'] = targetDocRef.id;
      myCopy['pairedUid'] = destinationUid;

      await targetDocRef.set(data);
      await myDocRef.set(myCopy);

      return targetDocRef.id;
    }

    final docRef = await FirebaseFirestore.instance
        .collection('users')
        .doc(destinationUid)
        .collection('calendar_reminders')
        .add(data);
    
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

  Future<void> deleteCalendarReminder(String id, {String? targetUid}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final currentOwnerUid = targetUid ?? user.uid;
    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(currentOwnerUid)
        .collection('calendar_reminders')
        .doc(id);

    try {
      final snap = await docRef.get();
      if (snap.exists) {
        final data = snap.data();
        final pairedDocId = data?['pairedDocId'] as String?;
        final pairedUid = data?['pairedUid'] as String?;
        final scheduledByUid = data?['scheduledByUid'] as String?;
        final scheduledForUid = data?['scheduledForUid'] as String?;
        final title = data?['title'] as String?;
        final dateStr = data?['date'] as String?;

        // 1. Delete direct paired document if present
        if (pairedDocId != null && pairedDocId.isNotEmpty && pairedUid != null && pairedUid.isNotEmpty) {
          try {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(pairedUid)
                .collection('calendar_reminders')
                .doc(pairedDocId)
                .delete();
          } catch (e) {
            print("Error deleting paired reminder: $e");
          }
        }

        // 2. Fallback query deletion for older reminders without pairedDocId
        final otherUid = (currentOwnerUid == user.uid) ? (scheduledForUid ?? scheduledByUid) : user.uid;
        if (otherUid != null && otherUid.isNotEmpty && otherUid != currentOwnerUid && title != null && dateStr != null) {
          try {
            final otherSnap = await FirebaseFirestore.instance
                .collection('users')
                .doc(otherUid)
                .collection('calendar_reminders')
                .where('title', isEqualTo: title)
                .where('date', isEqualTo: dateStr)
                .get();

            for (var otherDoc in otherSnap.docs) {
              await otherDoc.reference.delete();
            }
          } catch (e) {
            print("Error deleting matching paired reminder via fallback: $e");
          }
        }
      }
    } catch (e) {
      print("Error looking up reminder before delete: $e");
    }

    await docRef.delete();
  }

  Future<void> updateCalendarReminder(CalendarReminder reminder, {String? targetUid}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || reminder.id == null) return;
    
    final destinationUid = targetUid ?? user.uid;
    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(destinationUid)
        .collection('calendar_reminders')
        .doc(reminder.id);

    try {
      final snap = await docRef.get();
      if (snap.exists) {
        final data = snap.data();
        final pairedDocId = data?['pairedDocId'] as String?;
        final pairedUid = data?['pairedUid'] as String?;

        if (pairedDocId != null && pairedUid != null) {
          try {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(pairedUid)
                .collection('calendar_reminders')
                .doc(pairedDocId)
                .update(reminder.toMap());
          } catch (e) {
            print("Error updating paired reminder: $e");
          }
        }
      }
    } catch (e) {
      print("Error looking up reminder before update: $e");
    }

    await docRef.update(reminder.toMap());
  }

  Stream<List<CalendarReminder>> getAllCalendarRemindersStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();
    
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('calendar_reminders')
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
          return CalendarReminder.fromMap(doc.data(), doc.id);
        }).toList());
  }

  // Note Methods (Firebase Firestore)
  Future<String> insertNote(Note note) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return '';
    
    final docRef = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notes')
        .add({
      ...note.toMap(),
      'ownerUid': user.uid,
      'sharedWith': [],
    });
        
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
        
    final own = querySnapshot.docs
        .map((doc) => Note.fromMap(doc.data(), doc.id))
        .toList();

    final sharedSnapshot = await FirebaseFirestore.instance
        .collectionGroup('notes')
        .where('sharedWith', arrayContains: user.uid)
        .get();

    final shared = sharedSnapshot.docs
        .map((doc) => Note.fromMap(doc.data(), doc.id, ownerUid: doc.data()['ownerUid']))
        .toList();

    final merged = [...own, ...shared];
    merged.sort((a, b) {
      if (a.isStarred && !b.isStarred) return -1;
      if (!a.isStarred && b.isStarred) return 1;
      return b.date.compareTo(a.date);
    });
    return merged;
  }

  Stream<List<Note>> getNotesStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();
    
    final controller = StreamController<List<Note>>();
    List<Note> ownNotes = [];
    final Map<String, Note> sharedNotesMap = {};
    final Map<String, StreamSubscription> approvedItemSubscriptions = {};

    void emitMerged() {
      final Map<String, Note> allNotesMap = {};
      for (var note in ownNotes) {
        if (note.id != null) allNotesMap[note.id!] = note;
      }
      for (var note in sharedNotesMap.values) {
        if (note.id != null) allNotesMap[note.id!] = note;
      }

      final merged = allNotesMap.values.toList();
      merged.sort((a, b) {
        if (a.isStarred && !b.isStarred) return -1;
        if (!a.isStarred && b.isStarred) return 1;
        return b.date.compareTo(a.date);
      });
      if (!controller.isClosed) {
        controller.add(merged);
      }
    }

    // 1. Listen to own notes
    final ownSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notes')
        .snapshots()
        .map((snap) => snap.docs.map((doc) => Note.fromMap(doc.data(), doc.id)).toList())
        .listen((notes) {
          ownNotes = notes;
          emitMerged();
        }, onError: (err) {
          print("Error reading own notes: $err");
        });

    // 2. Listen to notes via collectionGroup where sharedWith contains user.uid
    final sharedGroupSub = FirebaseFirestore.instance
        .collectionGroup('notes')
        .where('sharedWith', arrayContains: user.uid)
        .snapshots()
        .listen((snap) {
          for (var doc in snap.docs) {
            final data = doc.data();
            final note = Note.fromMap(data, doc.id, ownerUid: data['ownerUid']);
            if (note.id != null) {
              sharedNotesMap[note.id!] = note;
            }
          }
          emitMerged();
        }, onError: (err) {
          print("Error reading shared notes group: $err");
        });

    // 3. Listen live to approved collaboration requests for notes
    final approvedReqsSub = FirebaseFirestore.instance
        .collection('collaboration_requests')
        .where('receiverUid', isEqualTo: user.uid)
        .where('type', isEqualTo: 'note')
        .where('status', isEqualTo: 'approved')
        .snapshots()
        .listen((snap) {
          final activeNoteIds = <String>{};

          for (var doc in snap.docs) {
            final data = doc.data();
            final senderUid = data['senderUid'] as String?;
            final itemId = data['itemId'] as String?;

            if (senderUid != null && itemId != null) {
              activeNoteIds.add(itemId);

              if (!approvedItemSubscriptions.containsKey(itemId)) {
                final sub = FirebaseFirestore.instance
                    .collection('users')
                    .doc(senderUid)
                    .collection('notes')
                    .doc(itemId)
                    .snapshots()
                    .listen((noteSnap) {
                      if (noteSnap.exists && noteSnap.data() != null) {
                        final noteData = noteSnap.data()!;
                        final note = Note.fromMap(noteData, noteSnap.id, ownerUid: senderUid);
                        if (note.id != null) {
                          sharedNotesMap[note.id!] = note;
                          emitMerged();
                        }
                      } else {
                        sharedNotesMap.remove(itemId);
                        emitMerged();
                      }
                    }, onError: (err) {
                      print("Error listening to shared note $itemId: $err");
                    });
                approvedItemSubscriptions[itemId] = sub;
              }
            }
          }

          final keysToRemove = approvedItemSubscriptions.keys.where((k) => !activeNoteIds.contains(k)).toList();
          for (var key in keysToRemove) {
            approvedItemSubscriptions[key]?.cancel();
            approvedItemSubscriptions.remove(key);
            sharedNotesMap.remove(key);
          }
          emitMerged();
        }, onError: (err) {
          print("Error reading approved collaboration requests: $err");
        });

    controller.onCancel = () {
      ownSub.cancel();
      sharedGroupSub.cancel();
      approvedReqsSub.cancel();
      for (var sub in approvedItemSubscriptions.values) {
        sub.cancel();
      }
      approvedItemSubscriptions.clear();
    };

    return controller.stream;
  }

  Future<void> updateNote(Note note) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || note.id == null) return;
    
    final targetUid = note.ownerUid ?? user.uid;
    
    await FirebaseFirestore.instance
        .collection('users')
        .doc(targetUid)
        .collection('notes')
        .doc(note.id)
        .update(note.toMap());
  }

  Future<void> deleteNote(String id, {String? ownerUid}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final targetUid = ownerUid ?? user.uid;
    if (targetUid != user.uid) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(targetUid)
          .collection('notes')
          .doc(id)
          .update({
            'sharedWith': FieldValue.arrayRemove([user.uid])
          });
    } else {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('notes')
          .doc(id)
          .delete();
    }
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
  Timestamp? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value;
    if (value is int) {
      return Timestamp.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return Timestamp.fromDate(parsed);
      }
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getChecklists() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    
    List<Map<String, dynamic>> own = [];
    try {
      final ownSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('checklists')
          .orderBy('createdAt', descending: true)
          .get();
      own = ownSnap.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
    } catch (e) {
      print("Error fetching own checklists: $e");
      try {
        final ownSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('checklists')
            .get();
        own = ownSnap.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
      } catch (e2) {
        print("Fallback fetching own checklists failed: $e2");
      }
    }

    List<Map<String, dynamic>> shared = [];
    try {
      final sharedSnap = await FirebaseFirestore.instance
          .collectionGroup('checklists')
          .where('sharedWith', arrayContains: user.uid)
          .get();
      shared = sharedSnap.docs.map((doc) {
        final data = doc.data();
        return {...data, 'id': doc.id, 'ownerUid': data['ownerUid']};
      }).toList();
    } catch (e) {
      print("Error fetching shared checklists (index might be missing): $e");
    }

    final merged = [...own, ...shared];
    try {
      merged.sort((a, b) {
        final aTime = _parseTimestamp(a['createdAt']);
        final bTime = _parseTimestamp(b['createdAt']);
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });
    } catch (e) {
      print("Error sorting checklists: $e");
    }
    return merged;
  }

  Stream<List<Map<String, dynamic>>> getChecklistsStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();
    
    final controller = StreamController<List<Map<String, dynamic>>>();
    List<Map<String, dynamic>> ownLists = [];
    List<Map<String, dynamic>> sharedLists = [];

    void emitMerged() {
      final merged = [...ownLists, ...sharedLists];
      try {
        merged.sort((a, b) {
          final aTime = _parseTimestamp(a['createdAt']);
          final bTime = _parseTimestamp(b['createdAt']);
          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return bTime.compareTo(aTime);
        });
      } catch (e) {
        print("Error sorting stream checklists: $e");
      }
      if (!controller.isClosed) {
        controller.add(merged);
      }
    }

    StreamSubscription? ownSub;
    StreamSubscription? sharedSub;

    try {
      ownSub = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('checklists')
          .snapshots()
          .map((snap) => snap.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList())
          .listen((lists) {
            ownLists = lists;
            emitMerged();
          }, onError: (err) {
            print("Error reading own checklists in stream: $err");
          });
    } catch (e) {
      print("Error subscribing to own checklists: $e");
    }

    try {
      sharedSub = FirebaseFirestore.instance
          .collectionGroup('checklists')
          .where('sharedWith', arrayContains: user.uid)
          .snapshots()
          .map((snap) => snap.docs.map((doc) {
            final data = doc.data();
            return {...data, 'id': doc.id, 'ownerUid': data['ownerUid']};
          }).toList())
          .listen((lists) {
            sharedLists = lists;
            emitMerged();
          }, onError: (err) {
            print("Error reading shared checklists in stream (index might be missing): $err");
            emitMerged();
          });
    } catch (e) {
      print("Error subscribing to shared checklists: $e");
    }

    controller.onCancel = () {
      ownSub?.cancel();
      sharedSub?.cancel();
    };

    return controller.stream;
  }

  Future<void> createChecklist(String title, int iconCode, int colorValue) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('checklists').add({
      'title': title,
      'iconCode': iconCode,
      'colorValue': colorValue,
      'createdAt': FieldValue.serverTimestamp(),
      'ownerUid': user.uid,
      'sharedWith': [],
    });
  }

  Future<void> deleteChecklist(String id, {String? ownerUid}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final targetUid = ownerUid ?? user.uid;
    if (targetUid != user.uid) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(targetUid)
          .collection('checklists')
          .doc(id)
          .update({
            'sharedWith': FieldValue.arrayRemove([user.uid])
          });
    } else {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('checklists').doc(id).delete();
    }
  }

  Future<void> addChecklistItem(String listId, String text, {String? ownerUid}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final targetUid = ownerUid ?? user.uid;
    final myUsername = await getCurrentUsername();

    String itemText = text;
    if (myUsername != null && myUsername.isNotEmpty) {
      if (!RegExp(r'\s*\(by\s+[^\)]+\)$').hasMatch(itemText)) {
        itemText = '${itemText.trim()} (by $myUsername)';
      }
    }

    await FirebaseFirestore.instance.collection('users').doc(targetUid).collection('checklists').doc(listId).collection('items').add({
      'text': itemText,
      'isChecked': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> toggleChecklistItem(String listId, String itemId, bool isChecked, {String? ownerUid}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final targetUid = ownerUid ?? user.uid;
    await FirebaseFirestore.instance.collection('users').doc(targetUid).collection('checklists').doc(listId).collection('items').doc(itemId).update({
      'isChecked': isChecked,
    });
  }

  Future<void> deleteChecklistItem(String listId, String itemId, {String? ownerUid}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final targetUid = ownerUid ?? user.uid;
    await FirebaseFirestore.instance.collection('users').doc(targetUid).collection('checklists').doc(listId).collection('items').doc(itemId).delete();
  }

  Future<void> resetChecklistItems(String listId, {String? ownerUid}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final targetUid = ownerUid ?? user.uid;
    final items = await FirebaseFirestore.instance.collection('users').doc(targetUid).collection('checklists').doc(listId).collection('items').get();
    final batch = FirebaseFirestore.instance.batch();
    for (var doc in items.docs) {
      batch.update(doc.reference, {'isChecked': false});
    }
    await batch.commit();
  }

  Stream<List<Map<String, dynamic>>> getChecklistItemsStream(String listId, {String? ownerUid}) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();
    final targetUid = ownerUid ?? user.uid;
    return FirebaseFirestore.instance.collection('users').doc(targetUid).collection('checklists').doc(listId).collection('items').orderBy('createdAt', descending: false).snapshots().map((snap) => snap.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList());
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

  Future<void> saveShiftRoster(
    String employeeName, 
    String monthLabel, 
    List<Map<String, dynamic>> shifts, {
    required String rosterMonth, 
    required String rawJson,
    String? rosterImageUrl,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final batch = FirebaseFirestore.instance.batch();
    final monthRef = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('shifts').doc(rosterMonth);
    
    final Map<String, dynamic> docData = {
      'employee_name': employeeName,
      'month_label': monthLabel,
      'last_updated': FieldValue.serverTimestamp(),
      'raw_json': rawJson,
    };
    if (rosterImageUrl != null) {
      docData['roster_image_url'] = rosterImageUrl;
    }
    
    batch.set(monthRef, docData, SetOptions(merge: true));

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

  Future<void> updateSingleShift(String date, Map<String, dynamic> shiftMap) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final month = date.substring(0, 7);
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('shifts')
        .doc(month)
        .collection('daily_shifts')
        .doc(date)
        .set(shiftMap, SetOptions(merge: true));
  }

  // User Preference Methods
  Future<Map<String, dynamic>> getUserPreferences() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return {};
    
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (!doc.exists) {
      // Default preferences: ONLY Gold is enabled by default
      return {
        'enabledModules': ['gold']
      };
    }
    
    final data = doc.data() ?? {};
    if (!data.containsKey('enabledModules')) {
      return {
        'enabledModules': ['gold']
      };
    }
    
    return data;
  }

  Future<void> updateUserPreferences(List<String> enabledModules) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'enabledModules': enabledModules,
    }, SetOptions(merge: true));
  }

  // Auth Methods
  Future<void> logoutAndClearData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  // Collaboration Methods
  Future<String> getCurrentUsername() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return '';
    if (user.displayName != null && user.displayName!.isNotEmpty) {
      return user.displayName!;
    }
    final snap = await FirebaseFirestore.instance
        .collection('usernames')
        .where('uid', isEqualTo: user.uid)
        .limit(1)
        .get();
    if (snap.docs.isNotEmpty) {
      return snap.docs.first.id;
    }
    return user.email ?? '';
  }

  Future<String?> getNotesPin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (doc.exists) {
      return doc.data()?['notesPin'] as String?;
    }
    return null;
  }

  Future<void> setNotesPin(String pin) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set({
          'notesPin': pin,
        }, SetOptions(merge: true));
  }

  Future<String> getUsernameFromUid(String uid) async {
    final snap = await FirebaseFirestore.instance
        .collection('usernames')
        .where('uid', isEqualTo: uid)
        .limit(1)
        .get();
    if (snap.docs.isNotEmpty) {
      return snap.docs.first.id;
    }
    return 'User';
  }

  Future<void> removeCollaborator({
    required String itemId,
    required String type,
    required String collaboratorUid,
    String? ownerUid,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final targetOwnerUid = ownerUid ?? user.uid;
    final subcollection = type == 'note' ? 'notes' : 'checklists';
    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(targetOwnerUid)
        .collection(subcollection)
        .doc(itemId);

    await docRef.update({
      'sharedWith': FieldValue.arrayRemove([collaboratorUid])
    });

    final requestsSnap = await FirebaseFirestore.instance
        .collection('collaboration_requests')
        .where('itemId', isEqualTo: itemId)
        .where('type', isEqualTo: type)
        .get();

    for (final doc in requestsSnap.docs) {
      final data = doc.data();
      if ((data['senderUid'] == targetOwnerUid && data['receiverUid'] == collaboratorUid) ||
          (data['senderUid'] == collaboratorUid && data['receiverUid'] == targetOwnerUid)) {
        await doc.reference.delete();
      }
    }
  }

  Future<List<Map<String, String>>> getAllUsers() async {
    final snap = await FirebaseFirestore.instance.collection('usernames').get();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    List<String>? allowed;
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (userDoc.exists && userDoc.data() != null && userDoc.data()!.containsKey('allowedCollaborators')) {
        allowed = List<String>.from(userDoc.data()!['allowedCollaborators'] ?? []);
      }
    } catch (_) {}

    final allUsers = snap.docs.map((doc) {
      final data = doc.data();
      return {
        'username': doc.id,
        'email': (data['email'] ?? '').toString(),
        'uid': (data['uid'] ?? '').toString(),
      };
    }).where((u) => u['uid'] != user.uid && u['uid']!.isNotEmpty).toList();

    if (allowed != null) {
      return allUsers.where((u) =>
        allowed!.contains(u['username']) || allowed.contains(u['uid'])
      ).toList();
    }

    return allUsers;
  }

  Future<void> sendCollaborationRequest({
    required String itemId,
    required String itemTitle,
    required String type, // 'note' or 'checklist'
    required String receiverUid,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    // Check admin allowedCollaborators permission
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (userDoc.exists && userDoc.data() != null && userDoc.data()!.containsKey('allowedCollaborators')) {
        final allowed = List<String>.from(userDoc.data()!['allowedCollaborators'] ?? []);
        final receiverUsername = await getUsernameFromUid(receiverUid);
        if (!allowed.contains(receiverUid) && !allowed.contains(receiverUsername)) {
          throw Exception("Admin permission required: Collaboration with user is not authorized.");
        }
      }
    } catch (e) {
      if (e.toString().contains("Admin permission required")) rethrow;
    }

    final senderUsername = await getCurrentUsername();
    
    // First, initialize ownerUid on the original item if not already set
    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection(type == 'note' ? 'notes' : 'checklists')
        .doc(itemId);
        
    await docRef.update({
      'ownerUid': user.uid,
    }).catchError((_) {});

    await FirebaseFirestore.instance.collection('collaboration_requests').add({
      'senderUid': user.uid,
      'senderUsername': senderUsername,
      'receiverUid': receiverUid,
      'type': type,
      'itemId': itemId,
      'title': itemTitle,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<Map<String, dynamic>>> getIncomingRequestsStream(String type) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();
    
    return FirebaseFirestore.instance
        .collection('collaboration_requests')
        .where('receiverUid', isEqualTo: user.uid)
        .where('type', isEqualTo: type)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList());
  }

  Future<void> respondToCollaborationRequest(String requestId, bool approve) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final requestRef = FirebaseFirestore.instance.collection('collaboration_requests').doc(requestId);
    
    if (approve) {
      final snap = await requestRef.get();
      if (!snap.exists) return;
      final data = snap.data()!;
      final senderUid = data['senderUid'];
      final itemId = data['itemId'];
      final type = data['type'];
      final senderUsername = data['senderUsername'] as String?;

      final itemRef = FirebaseFirestore.instance
          .collection('users')
          .doc(senderUid)
          .collection(type == 'note' ? 'notes' : 'checklists')
          .doc(itemId);
          
      // Update item to add receiver to sharedWith
      try {
        await itemRef.update({
          'sharedWith': FieldValue.arrayUnion([user.uid]),
          'ownerUid': senderUid,
        });

        if (senderUsername != null && senderUsername.isNotEmpty) {
          final itemSnap = await itemRef.get();
          if (itemSnap.exists && itemSnap.data() != null) {
            final itemData = itemSnap.data()!;
            final Map<String, dynamic> updates = {};

            if (type == 'note') {
              final content = itemData['content'] as String? ?? '';
              if (content.isNotEmpty) {
                final signedContent = content.split('\n').map((line) {
                  if (line.trim().isEmpty) return line;
                  if (RegExp(r'\s*\(by\s+[^\)]+\)$').hasMatch(line)) return line;
                  return '$line (by $senderUsername)';
                }).join('\n');
                updates['content'] = signedContent;
              }

              final checklistItems = itemData['checklistItems'] as List<dynamic>?;
              if (checklistItems != null && checklistItems.isNotEmpty) {
                final signedChecklist = checklistItems.map((item) {
                  final text = item['text'] as String? ?? '';
                  if (text.trim().isEmpty || RegExp(r'\s*\(by\s+[^\)]+\)$').hasMatch(text)) {
                    return item;
                  }
                  return {...Map<String, dynamic>.from(item), 'text': '$text (by $senderUsername)'};
                }).toList();
                updates['checklistItems'] = signedChecklist;
              }
            } else if (type == 'checklist') {
              final itemsSnap = await itemRef.collection('items').get();
              for (var doc in itemsSnap.docs) {
                final text = doc.data()['text'] as String? ?? '';
                if (text.isNotEmpty && !RegExp(r'\s*\(by\s+[^\)]+\)$').hasMatch(text)) {
                  await doc.reference.update({'text': '$text (by $senderUsername)'});
                }
              }
            }

            if (updates.isNotEmpty) {
              await itemRef.update(updates);
            }
          }
        }
      } catch (e) {
        print("Direct item update failed (expected due to security rules): $e");
      }
      
      await requestRef.update({'status': 'approved'});
    } else {
      await requestRef.update({'status': 'rejected'});
    }
  }

  // Buddy Link / Scheduling Permissions Methods
  Future<void> sendBuddyLinkRequest(String receiverUsername) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("User not logged in");

    final senderUsername = await getCurrentUsername() ?? user.email ?? 'User';

    // Find receiver uid
    final receiverSnap = await FirebaseFirestore.instance
        .collection('usernames')
        .doc(receiverUsername)
        .get();

    if (!receiverSnap.exists) {
      throw Exception("User not found");
    }

    final receiverUid = receiverSnap.data()?['uid'];
    if (receiverUid == null) {
      throw Exception("Invalid user data");
    }

    if (receiverUid == user.uid) {
      throw Exception("Cannot link with yourself");
    }

    final linkId = "${user.uid}_$receiverUid";

    await FirebaseFirestore.instance.collection('buddy_links').doc(linkId).set({
      'senderUid': user.uid,
      'senderUsername': senderUsername,
      'receiverUid': receiverUid,
      'receiverUsername': receiverUsername,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> respondToBuddyRequest(String linkId, String status) async {
    if (status == 'rejected') {
      await FirebaseFirestore.instance.collection('buddy_links').doc(linkId).delete();
    } else {
      await FirebaseFirestore.instance.collection('buddy_links').doc(linkId).update({
        'status': status,
      });
    }
  }

  Stream<List<Map<String, dynamic>>> getIncomingBuddyRequestsStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('buddy_links')
        .where('receiverUid', isEqualTo: user.uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.docs.map((doc) => {
              ...doc.data(),
              'id': doc.id,
            }).toList());
  }

  Future<void> removeBuddyLink(String linkId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('buddy_links').doc(linkId).delete();
  }

  Stream<List<Map<String, dynamic>>> getApprovedBuddiesStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();

    late StreamController<List<Map<String, dynamic>>> controller;
    StreamSubscription? sub1;
    StreamSubscription? sub2;

    List<Map<String, dynamic>> list1 = [];
    List<Map<String, dynamic>> list2 = [];

    void emitBuddies() {
      final Map<String, Map<String, dynamic>> map = {};
      for (var b in list1) {
        map[b['linkId']] = b;
      }
      for (var b in list2) {
        map[b['linkId']] = b;
      }
      if (!controller.isClosed) {
        controller.add(map.values.toList());
      }
    }

    controller = StreamController<List<Map<String, dynamic>>>.broadcast(
      onListen: () {
        emitBuddies();

        sub1 = FirebaseFirestore.instance
            .collection('buddy_links')
            .where('senderUid', isEqualTo: user.uid)
            .where('status', isEqualTo: 'approved')
            .snapshots()
            .listen((snap) {
          list1 = snap.docs.map((doc) {
            final val = doc.data();
            final buddyUid = (val['receiverUid'] ?? '').toString();
            final buddyUsername = (val['receiverUsername'] ?? 'User').toString();
            return {
              'linkId': doc.id,
              'uid': buddyUid,
              'username': buddyUsername,
              'receiverUid': buddyUid,
              'receiverUsername': buddyUsername,
            };
          }).toList();
          emitBuddies();
        }, onError: (_) => emitBuddies());

        sub2 = FirebaseFirestore.instance
            .collection('buddy_links')
            .where('receiverUid', isEqualTo: user.uid)
            .where('status', isEqualTo: 'approved')
            .snapshots()
            .listen((snap) {
          list2 = snap.docs.map((doc) {
            final val = doc.data();
            final buddyUid = (val['senderUid'] ?? '').toString();
            final buddyUsername = (val['senderUsername'] ?? 'User').toString();
            return {
              'linkId': doc.id,
              'uid': buddyUid,
              'username': buddyUsername,
              'receiverUid': buddyUid,
              'receiverUsername': buddyUsername,
            };
          }).toList();
          emitBuddies();
        }, onError: (_) => emitBuddies());
      },
      onCancel: () {
        sub1?.cancel();
        sub2?.cancel();
      },
    );

    return controller.stream;
  }

  Stream<List<NotificationHistory>> getNotificationHistoryStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => NotificationHistory.fromMap(doc.data(), doc.id))
            .toList());
  }
}
