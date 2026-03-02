import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/task.dart';
import '../models/note.dart';
import '../models/daily_reminder.dart';
import '../models/gold_price.dart';


class StorageService {
  static final StorageService _instance = StorageService._internal();
  static Database? _database;
  static const int _databaseVersion = 16;  // Version 16: New gold prices schema
  static const String _authTokenKey = 'auth_token';
  static const String _userKey = 'user_data';

  factory StorageService() {
    return _instance;
  }

  StorageService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    // For web, use in-memory database (data won't persist on refresh)
    if (kIsWeb) {
      return await openDatabase(
        inMemoryDatabasePath,
        version: _databaseVersion,
        onCreate: (db, version) async {
          await _createTables(db);
        },
      );
    }
    
    // For mobile, use persistent database
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'remindbuddy.db');

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        print('Upgrading database from $oldVersion to $newVersion');
        
        // Migration for version 2: Add isAnnoying column to tasks
        if (oldVersion < 2) {
          try {
            await db.execute('ALTER TABLE tasks ADD COLUMN isAnnoying INTEGER DEFAULT 0');
          } catch (e) { print("isAnnoying column error: $e"); }
        }
        
        // Migration for version 3: Add daily_reminders table
        if (oldVersion < 3) {
          try {
            await db.execute(
              'CREATE TABLE daily_reminders(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, description TEXT, time TEXT, isActive INTEGER, isAnnoying INTEGER)',
            );
          } catch (e) { print("daily_reminders table error: $e"); }
        }
        
        // Migration for version 4: Add checklists tables
        if (oldVersion < 4) {
          try {
            await db.execute(
              'CREATE TABLE checklists(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, iconCode INTEGER, color INTEGER)',
            );
            await db.execute(
              'CREATE TABLE checklist_items(id INTEGER PRIMARY KEY AUTOINCREMENT, checklistId INTEGER, text TEXT, isChecked INTEGER)',
            );
          } catch (e) { print("checklists table error: $e"); }
        }
        
        // Migration for version 5: Add gold_prices table
        if (oldVersion < 5) {
          try {
            await db.execute(
              'CREATE TABLE gold_prices(date TEXT PRIMARY KEY, price22k REAL, price24k REAL, city TEXT)',
            );
          } catch (e) { print("gold_prices table error: $e"); }
        }
        
        // Migration for version 6: Add gold_prices_history table
        if (oldVersion < 6) {
           try {
             await db.execute(
               'CREATE TABLE gold_prices_history(id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TEXT, price22k REAL, price24k REAL, city TEXT)',
             );
             // Migrate old data
             // await db.execute('INSERT INTO gold_prices_history (timestamp, price22k, price24k, city) SELECT date, price22k, price24k, city FROM gold_prices');
           } catch (e) { print("gold_prices_history table error: $e"); }
        }
        
        // Migration for version 7: Add Shifts tables
        if (oldVersion < 7) {
           try {
             await db.execute(
               'CREATE TABLE shifts(id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT UNIQUE, shift_type TEXT, start_time TEXT, end_time TEXT, is_week_off INTEGER)',
             );
             await db.execute(
               'CREATE TABLE shift_metadata(id INTEGER PRIMARY KEY, employee_name TEXT, month TEXT)',
             );
           } catch (e) { print("Shifts table error: $e"); }
        }
        
        // Migration for version 8: Add roster_month column for multi-month support
        if (oldVersion < 8) {
           try {
             // Add roster_month column to shifts table
             await db.execute('ALTER TABLE shifts ADD COLUMN roster_month TEXT');
             // Add roster_month column to shift_metadata table
             await db.execute('ALTER TABLE shift_metadata ADD COLUMN roster_month TEXT');
             
             // Update existing shifts with their month from the date
             await db.execute('''
               UPDATE shifts 
               SET roster_month = substr(date, 1, 7)
               WHERE roster_month IS NULL
             ''');
             
             print("✅ Added multi-month support to shifts tables");
           } catch (e) { print("Multi-month shifts migration error: $e"); }
        }

        
        // Migration for version 9: Add sync columns (isSynced, remoteId, updatedAt)
        if (oldVersion < 9) {
           try {
              // Add sync columns to tasks
              await db.execute('ALTER TABLE tasks ADD COLUMN remoteId TEXT');
              await db.execute('ALTER TABLE tasks ADD COLUMN isSynced INTEGER DEFAULT 0');
              await db.execute('ALTER TABLE tasks ADD COLUMN updatedAt TEXT');

              // Add sync columns to notes
              await db.execute('ALTER TABLE notes ADD COLUMN remoteId TEXT');
              await db.execute('ALTER TABLE notes ADD COLUMN isSynced INTEGER DEFAULT 0');
              await db.execute('ALTER TABLE notes ADD COLUMN updatedAt TEXT');
              
              print("✅ Added sync columns for offline-first architecture");
           } catch (e) {
              print("Sync migration error: $e");
           }
        }

        
        // Migration for version 10: Add sync columns to remaining tables
        if (oldVersion < 10) {
           try {
              // daily_reminders
              await db.execute('ALTER TABLE daily_reminders ADD COLUMN remoteId TEXT');
              await db.execute('ALTER TABLE daily_reminders ADD COLUMN isSynced INTEGER DEFAULT 0');
              await db.execute('ALTER TABLE daily_reminders ADD COLUMN updatedAt TEXT');
              
              // checklists
              await db.execute('ALTER TABLE checklists ADD COLUMN remoteId TEXT');
              await db.execute('ALTER TABLE checklists ADD COLUMN isSynced INTEGER DEFAULT 0');
              await db.execute('ALTER TABLE checklists ADD COLUMN updatedAt TEXT');
              
              // checklist_items
              await db.execute('ALTER TABLE checklist_items ADD COLUMN remoteId TEXT');
              await db.execute('ALTER TABLE checklist_items ADD COLUMN isSynced INTEGER DEFAULT 0');
              await db.execute('ALTER TABLE checklist_items ADD COLUMN updatedAt TEXT');
              
              // shifts
              await db.execute('ALTER TABLE shifts ADD COLUMN remoteId TEXT');
              await db.execute('ALTER TABLE shifts ADD COLUMN isSynced INTEGER DEFAULT 0');
              await db.execute('ALTER TABLE shifts ADD COLUMN updatedAt TEXT');
              
              // shift_metadata
              await db.execute('ALTER TABLE shift_metadata ADD COLUMN remoteId TEXT');
              await db.execute('ALTER TABLE shift_metadata ADD COLUMN isSynced INTEGER DEFAULT 0');
              await db.execute('ALTER TABLE shift_metadata ADD COLUMN updatedAt TEXT');
              
              print("✅ Added sync columns to all remaining tables");
           } catch (e) {
              print("Sync migration v10 error: $e");
           }
        }

        // Migration for version 11: Fix missing sync columns (Safety Check)
        // If v9 or v10 failed or were skipped, this ensures columns exist.
        if (oldVersion < 11) {
            print("Running safety migration v11...");
            final tables = ['tasks', 'notes', 'daily_reminders', 'checklists', 'checklist_items', 'shifts', 'shift_metadata'];
            
            for (var table in tables) {
                try {
                    // Check if column exists by trying to add it. 
                    // SQLite doesn't have "IF NOT EXISTS" for ADD COLUMN, so we use try-catch block.
                    // If it fails, it likely exists or there's another error, which is fine.
                    try { await db.execute('ALTER TABLE $table ADD COLUMN remoteId TEXT'); } catch(e) {}
                    try { await db.execute('ALTER TABLE $table ADD COLUMN isSynced INTEGER DEFAULT 0'); } catch(e) {}
                    try { await db.execute('ALTER TABLE $table ADD COLUMN updatedAt TEXT'); } catch(e) {}
                } catch(e) {
                    print("Safety migration error for $table: $e");
                }
            }
            print("✅ Safety migration v11 database check complete.");
        }

        // Migration for version 12: Ensure Sync Columns for Fresh Installs
        if (oldVersion < 12) {
            print("Running migration v12: Ensuring sync columns for fresh installs...");
            final tables = ['tasks', 'notes', 'daily_reminders', 'checklists', 'checklist_items', 'shifts', 'shift_metadata'];
            
            for (var table in tables) {
                try {
                    await db.execute('ALTER TABLE $table ADD COLUMN remoteId TEXT');
                } catch(e) { /* Column likely exists */ }
                try {
                    await db.execute('ALTER TABLE $table ADD COLUMN isSynced INTEGER DEFAULT 0');
                } catch(e) { /* Column likely exists */ }
                try {
                    await db.execute('ALTER TABLE $table ADD COLUMN updatedAt TEXT');
                } catch(e) { /* Column likely exists */ }
            }
            print("✅ Migration v12 database check complete.");
        } // Close migration 12

        // Migration for version 13: Add monthly_rosters
        if (oldVersion < 13) {
            try {
              await db.execute(
                'CREATE TABLE IF NOT EXISTS monthly_rosters(roster_month TEXT PRIMARY KEY, month TEXT, json_data TEXT, remoteId TEXT, isSynced INTEGER DEFAULT 0, updatedAt TEXT)',
              );
            } catch (e) { print("Error creating monthly_rosters: $e"); }
        }

        // Migration for version 14: Add deleted_records
        if (oldVersion < 14) {
             print("Running migration v14: Creating deleted_records table...");
             try {
               await db.execute(
                 'CREATE TABLE IF NOT EXISTS deleted_records(id INTEGER PRIMARY KEY AUTOINCREMENT, collectionName TEXT, remoteId TEXT)',
               );
             } catch (e) { print("Error creating deleted_records: $e"); }
        }

        // Migration for version 16: New gold prices schema
        if (oldVersion < 16) {
             print("Running migration v16: Recreating gold_prices table...");
             try {
               await db.execute('DROP TABLE IF EXISTS gold_prices');
               await db.execute('DROP TABLE IF EXISTS gold_prices_history');
               await db.execute(
                 'CREATE TABLE gold_prices(id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT UNIQUE, timestamp TEXT, price REAL, priceChange REAL, remoteId TEXT, isSynced INTEGER DEFAULT 0, updatedAt TEXT)',
               );
             } catch (e) { print("Error recreating gold_prices: $e"); }
        }
      },
    );
  }

  Future<void> _createTables(Database db) async {
    await db.execute(
      'CREATE TABLE tasks(id INTEGER PRIMARY KEY, title TEXT, description TEXT, date TEXT, time TEXT, repeat TEXT, isAnnoying INTEGER, remoteId TEXT, isSynced INTEGER DEFAULT 0, updatedAt TEXT)',
    );
    await db.execute(
      'CREATE TABLE notes(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, content TEXT, date TEXT, isLocked INTEGER, remoteId TEXT, isSynced INTEGER DEFAULT 0, updatedAt TEXT)',
    );
    await db.execute(
      'CREATE TABLE daily_reminders(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, description TEXT, time TEXT, isActive INTEGER, isAnnoying INTEGER, remoteId TEXT, isSynced INTEGER DEFAULT 0, updatedAt TEXT)',
    );
    // Legacy table, kept for compatibility if needed or purely replaced by history
    await db.execute(
      'CREATE TABLE gold_prices(id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT UNIQUE, timestamp TEXT, price REAL, priceChange REAL, remoteId TEXT, isSynced INTEGER DEFAULT 0, updatedAt TEXT)',
    );
    await db.execute(
      'CREATE TABLE checklists(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, iconCode INTEGER, color INTEGER, remoteId TEXT, isSynced INTEGER DEFAULT 0, updatedAt TEXT)',
    );
    await db.execute(
      'CREATE TABLE checklist_items(id INTEGER PRIMARY KEY AUTOINCREMENT, checklistId INTEGER, text TEXT, isChecked INTEGER, remoteId TEXT, isSynced INTEGER DEFAULT 0, updatedAt TEXT)',
    );
    await db.execute(
      'CREATE TABLE shifts(id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT UNIQUE, shift_type TEXT, start_time TEXT, end_time TEXT, is_week_off INTEGER, roster_month TEXT, remoteId TEXT, isSynced INTEGER DEFAULT 0, updatedAt TEXT)',
    );
    await db.execute(
      'CREATE TABLE shift_metadata(id INTEGER PRIMARY KEY, employee_name TEXT, month TEXT, roster_month TEXT, remoteId TEXT, isSynced INTEGER DEFAULT 0, updatedAt TEXT)',
    );
    await db.execute(
      'CREATE TABLE monthly_rosters(roster_month TEXT PRIMARY KEY, month TEXT, json_data TEXT, remoteId TEXT, isSynced INTEGER DEFAULT 0, updatedAt TEXT)',
    );
    await db.execute(
      'CREATE TABLE shifts_data(month_year TEXT PRIMARY KEY, json_data TEXT, remoteId TEXT, isSynced INTEGER DEFAULT 0, updatedAt TEXT)',
    );
    await db.execute(
      'CREATE TABLE deleted_records(id INTEGER PRIMARY KEY AUTOINCREMENT, collectionName TEXT, remoteId TEXT)',
    );
  }


  Future<void> _recordDeletion(Database db, String tableName, String collectionName, int id) async {
    final maps = await db.query(tableName, where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty && maps.first['remoteId'] != null) {
       final remoteId = maps.first['remoteId'] as String;
       if (remoteId.isNotEmpty) {
           await db.insert('deleted_records', {
               'collectionName': collectionName,
               'remoteId': remoteId,
           });
       }
    }
  }

  Future<void> _recordDeletionByField(Database db, String tableName, String collectionName, String where, List<dynamic> whereArgs) async {
    final maps = await db.query(tableName, where: where, whereArgs: whereArgs);
    for (var map in maps) {
       if (map['remoteId'] != null) {
           final remoteId = map['remoteId'] as String;
           if (remoteId.isNotEmpty) {
               await db.insert('deleted_records', {
                   'collectionName': collectionName,
                   'remoteId': remoteId,
               });
           }
       }
    }
  }

  Future<List<Map<String, dynamic>>> getDeletedRecords() async {
      final db = await database;
      return await db.query('deleted_records');
  }

  Future<void> removeDeletedRecord(int id) async {
      final db = await database;
      await db.delete('deleted_records', where: 'id = ?', whereArgs: [id]);
  }
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
  Future<void> insertNote(Note note) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notes')
        .add(note.toMap());
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

  // Shift Methods
  Future<void> saveShiftRoster(String employeeName, String month, List<Map<String, dynamic>> shifts, {String? rosterMonth, String? rawJson, bool skipSyncFlag = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final effectiveRosterMonth = rosterMonth ?? (shifts.isNotEmpty ? shifts[0]['date'].toString().substring(0, 7) : month);
    
    final batch = FirebaseFirestore.instance.batch();
    
    final metadataRef = FirebaseFirestore.instance
        .collection('users').doc(user.uid)
        .collection('shift_metadata').doc(effectiveRosterMonth);
        
    batch.set(metadataRef, {
      'employee_name': employeeName,
      'month': month,
      'roster_month': effectiveRosterMonth,
      'raw_json': rawJson,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    
    for (var shift in shifts) {
      final date = shift['date'] as String;
      final shiftRef = FirebaseFirestore.instance
        .collection('users').doc(user.uid)
        .collection('shifts').doc(date);
        
      final shiftData = Map<String, dynamic>.from(shift);
      shiftData['roster_month'] = effectiveRosterMonth;
      batch.set(shiftRef, shiftData, SetOptions(merge: true));
    }
    
    await batch.commit();
    print('✅ Saved ${shifts.length} shifts for roster month: $effectiveRosterMonth to Firestore');
  }

  Future<Map<String, String>?> getShiftMetadata({String? rosterMonth}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    
    if (rosterMonth != null) {
      final doc = await FirebaseFirestore.instance
        .collection('users').doc(user.uid)
        .collection('shift_metadata').doc(rosterMonth).get();
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
        .collection('shift_metadata')
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
    
    Query q = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('shifts');
    if (rosterMonth != null) {
      q = q.where('roster_month', isEqualTo: rosterMonth);
    }
    final snap = await q.orderBy('date', descending: false).get();
    return snap.docs.map((d) => d.data() as Map<String, dynamic>).toList();
  }

  Future<Map<String, dynamic>?> getShiftForDate(String date) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    
    final doc = await FirebaseFirestore.instance
        .collection('users').doc(user.uid)
        .collection('shifts').doc(date).get();
        
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
        
    return snap.docs.map((d) => d.data() as Map<String, dynamic>).toList();
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
      
    return snap.docs.map((d) => d.data() as Map<String, dynamic>).toList();
  }

  Future<void> clearAllShifts({String? rosterMonth}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final batch = FirebaseFirestore.instance.batch();
    if (rosterMonth != null) {
      final metaRef = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('shift_metadata').doc(rosterMonth);
      batch.delete(metaRef);
      final shiftsSnap = await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('shifts').where('roster_month', isEqualTo: rosterMonth).get();
      for (var d in shiftsSnap.docs) { batch.delete(d.reference); }
      await batch.commit();
    } else {
      final metaSnap = await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('shift_metadata').get();
      final shiftsSnap = await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('shifts').get();
      for (var d in metaSnap.docs) { batch.delete(d.reference); }
      for (var d in shiftsSnap.docs) { batch.delete(d.reference); }
      await batch.commit();
    }
  }
  
  // Get list of available roster months
  Future<List<String>> getAvailableRosterMonths() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    
    final snap = await FirebaseFirestore.instance
      .collection('users').doc(user.uid)
      .collection('shift_metadata')
      .orderBy('roster_month', descending: true).get();
      
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
    final token = await getAuthToken();
    return token != null && token.isNotEmpty;
  }

  Future<void> logoutAndClearData() async {
    // 1. Clear Auth Token
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authTokenKey);
    await prefs.remove(_userKey);
    await prefs.remove('last_sync_time'); // Clear sync history

    // 2. Clear Local Database (Privacy: Don't keep user data after logout)
    final db = await database;
    await db.delete('tasks');
    await db.delete('notes');
    await db.delete('shifts');
    await db.delete('shift_metadata');
    await db.delete('monthly_rosters');
    await db.delete('checklists');
    await db.delete('checklist_items');
    await db.delete('daily_reminders');
    // We might keep gold prices as they are public data? But to be safe/clean:
    // await db.delete('gold_prices_history'); 
    
    print('🔒 User logged out and local data cleared.');
  }
}
