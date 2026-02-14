import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/task.dart';
import '../models/note.dart';
import '../models/daily_reminder.dart';
import '../models/gold_price.dart';


class StorageService {
  static final StorageService _instance = StorageService._internal();
  static Database? _database;
  static const int _databaseVersion = 8;  // Database version for multi-month shifts

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
      },
    );
  }

  Future<void> _createTables(Database db) async {
    await db.execute(
      'CREATE TABLE tasks(id INTEGER PRIMARY KEY, title TEXT, description TEXT, date TEXT, time TEXT, repeat TEXT, isAnnoying INTEGER)',
    );
    await db.execute(
      'CREATE TABLE notes(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, content TEXT, date TEXT, isLocked INTEGER)',
    );
    await db.execute(
      'CREATE TABLE daily_reminders(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, description TEXT, time TEXT, isActive INTEGER, isAnnoying INTEGER)',
    );
    // Legacy table, kept for compatibility if needed or purely replaced by history
    await db.execute(
      'CREATE TABLE gold_prices(date TEXT PRIMARY KEY, price22k REAL, price24k REAL, city TEXT)',
    );
    await db.execute(
      'CREATE TABLE gold_prices_history(id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TEXT, price22k REAL, price24k REAL, city TEXT)',
    );
    await db.execute(
      'CREATE TABLE checklists(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, iconCode INTEGER, color INTEGER)',
    );
    await db.execute(
      'CREATE TABLE checklist_items(id INTEGER PRIMARY KEY AUTOINCREMENT, checklistId INTEGER, text TEXT, isChecked INTEGER)',
    );
    await db.execute(
      'CREATE TABLE shifts(id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT UNIQUE, shift_type TEXT, start_time TEXT, end_time TEXT, is_week_off INTEGER, roster_month TEXT)',
    );
    await db.execute(
      'CREATE TABLE shift_metadata(id INTEGER PRIMARY KEY, employee_name TEXT, month TEXT, roster_month TEXT)',
    );
  }

  // Task Methods
  Future<void> insertTask(Task task) async {
    final db = await database;
    await db.insert(
      'tasks',
      task.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Task>> getTasks() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('tasks');
    return List.generate(maps.length, (i) {
      return Task(
        id: maps[i]['id'],
        title: maps[i]['title'],
        description: maps[i]['description'],
        date: maps[i]['date'],
        time: maps[i]['time'],
        repeat: maps[i]['repeat'],
        isAnnoying: maps[i]['isAnnoying'] == 1,
      );
    });
  }

  Future<List<Task>> getTasksForDate(String date) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'tasks',
      where: 'date = ?',
      whereArgs: [date],
    );
    return List.generate(maps.length, (i) => Task.fromJson(maps[i]));
  }

  Future<void> updateTask(Task task) async {
    final db = await database;
    await db.update(
      'tasks',
      task.toMap(),
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  Future<void> deleteTask(int id) async {
    final db = await database;
    await db.delete(
      'tasks',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearOldTasks(String today) async {
    final db = await database;
    await db.delete('tasks', where: 'date < ?', whereArgs: [today]);
  }

  // Note Methods
  Future<void> insertNote(Note note) async {
    final db = await database;
    await db.insert(
      'notes',
      note.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Note>> getNotes() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('notes', orderBy: "date DESC");
    return List.generate(maps.length, (i) => Note.fromMap(maps[i]));
  }

  Future<void> updateNote(Note note) async {
    final db = await database;
    await db.update(
      'notes',
      note.toMap(),
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  Future<void> deleteNote(int id) async {
    final db = await database;
    await db.delete(
      'notes',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Daily Reminder Methods
  Future<int> insertDailyReminder(DailyReminder reminder) async {
    final db = await database;
    return await db.insert(
      'daily_reminders',
      reminder.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<DailyReminder>> getDailyReminders() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('daily_reminders', orderBy: "time ASC");
    return List.generate(maps.length, (i) => DailyReminder.fromJson(maps[i]));
  }

  Future<List<DailyReminder>> getActiveDailyReminders() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'daily_reminders',
      where: 'isActive = ?',
      whereArgs: [1],
      orderBy: "time ASC",
    );
    return List.generate(maps.length, (i) => DailyReminder.fromJson(maps[i]));
  }

  Future<void> updateDailyReminder(DailyReminder reminder) async {
    final db = await database;
    await db.update(
      'daily_reminders',
      reminder.toMap(),
      where: 'id = ?',
      whereArgs: [reminder.id],
    );
  }

  Future<void> deleteDailyReminder(int id) async {
    final db = await database;
    await db.delete(
      'daily_reminders',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> toggleDailyReminderActive(int id, bool isActive) async {
    final db = await database;
    await db.update(
      'daily_reminders',
      {'isActive': isActive ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }


  // Checklist Methods
  Future<int> createChecklist(String title, int iconCode, int color) async {
    final db = await database;
    return await db.insert('checklists', {
      'title': title,
      'iconCode': iconCode,
      'color': color,
    });
  }

  Future<List<Map<String, dynamic>>> getChecklists() async {
    final db = await database;
    return await db.query('checklists');
  }

  Future<void> deleteChecklist(int id) async {
    final db = await database;
    await db.delete('checklists', where: 'id = ?', whereArgs: [id]);
    await db.delete('checklist_items', where: 'checklistId = ?', whereArgs: [id]);
  }

  Future<int> addChecklistItem(int checklistId, String text) async {
    final db = await database;
    return await db.insert('checklist_items', {
      'checklistId': checklistId,
      'text': text,
      'isChecked': 0,
    });
  }

  Future<List<Map<String, dynamic>>> getChecklistItems(int checklistId) async {
    final db = await database;
    return await db.query('checklist_items', where: 'checklistId = ?', whereArgs: [checklistId]);
  }

  Future<void> toggleChecklistItem(int id, bool isChecked) async {
    final db = await database;
    await db.update(
      'checklist_items',
      {'isChecked': isChecked ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteChecklistItem(int id) async {
    final db = await database;
    await db.delete('checklist_items', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> resetChecklistItems(int checklistId) async {
    final db = await database;
    await db.update(
      'checklist_items',
      {'isChecked': 0},
      where: 'checklistId = ?',
      whereArgs: [checklistId],
    );
  }

  // Gold Price Methods (Updated for History)
  Future<void> saveGoldPrice(GoldPrice price) async {
    final db = await database;
    // Save to legacy table (overwrites for the day)
    await db.insert(
      'gold_prices',
      price.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    
    // Save to history table (keeps all updates)
    // Add current timestamp if not present
    await db.insert(
      'gold_prices_history',
      {
        'timestamp': DateTime.now().toIso8601String(),
        'price22k': price.price22k,
        'price24k': price.price24k,
        'city': price.city,
      },
    );
  }

  Future<List<GoldPrice>> getGoldPriceHistory({int limit = 20}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'gold_prices_history',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    
    // Convert history format to GoldPrice
    return List.generate(maps.length, (i) {
        return GoldPrice(
           date: maps[i]['timestamp'].toString().split('T')[0], // Extract date part for display compatibility
           price22k: maps[i]['price22k'],
           price24k: maps[i]['price24k'],
           city: maps[i]['city'],
        );
    });
  }

  Future<double?> getPreviousGoldPrice() async {
     final db = await database;
     final List<Map<String, dynamic>> maps = await db.query(
      'gold_prices_history',
      orderBy: 'timestamp DESC',
      limit: 2,
    );
    
    if (maps.length < 2) return null;
    return maps[1]['price22k'] as double;
  }

  Future<List<GoldPrice>> getGoldPrices({int limit = 10}) async {
    // Return daily snapshot (legacy table)
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'gold_prices',
      orderBy: 'date DESC',
      limit: limit,
    );
    return List.generate(maps.length, (i) => GoldPrice.fromJson(maps[i]));
  }

  Future<GoldPrice?> getLatestGoldPrice() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'gold_prices_history',
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    
    return GoldPrice(
       date: maps[0]['timestamp'].toString().split('T')[0],
       price22k: maps[0]['price22k'],
       price24k: maps[0]['price24k'],
       city: maps[0]['city'],
    );
  }

  // Shift Methods
  Future<void> saveShiftRoster(String employeeName, String month, List<Map<String, dynamic>> shifts, {String? rosterMonth}) async {
    final db = await database;
    
    // Extract roster month from the first shift date if not provided
    final effectiveRosterMonth = rosterMonth ?? (shifts.isNotEmpty ? shifts[0]['date'].toString().substring(0, 7) : month);
    
    // Clear existing shifts for this specific roster month only
    await db.delete('shifts', where: 'roster_month = ?', whereArgs: [effectiveRosterMonth]);
    
    // Save or update metadata for this roster month
    await db.insert('shift_metadata', {
      'id': effectiveRosterMonth.hashCode % 1000000,  // Unique ID based on month
      'employee_name': employeeName,
      'month': month,
      'roster_month': effectiveRosterMonth,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    
    // Save shifts with roster_month
    for (var shift in shifts) {
      final shiftData = Map<String, dynamic>.from(shift);
      shiftData['roster_month'] = effectiveRosterMonth;
      await db.insert('shifts', shiftData, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    
    print('✅ Saved ${shifts.length} shifts for roster month: $effectiveRosterMonth');
  }

  Future<Map<String, String>?> getShiftMetadata({String? rosterMonth}) async {
    final db = await database;
    List<Map<String, dynamic>> maps;
    
    if (rosterMonth != null) {
      maps = await db.query('shift_metadata', where: 'roster_month = ?', whereArgs: [rosterMonth]);
    } else {
      // Get the most recent metadata
      maps = await db.query('shift_metadata', orderBy: 'id DESC', limit: 1);
    }
    
    if (maps.isEmpty) return null;
    
    return {
      'employee_name': maps[0]['employee_name'] as String,
      'month': maps[0]['month'] as String,
      'roster_month': maps[0]['roster_month'] as String? ?? maps[0]['month'] as String,
    };
  }

  Future<List<Map<String, dynamic>>> getAllShifts({String? rosterMonth}) async {
    final db = await database;
    if (rosterMonth != null) {
      return await db.query('shifts', where: 'roster_month = ?', whereArgs: [rosterMonth], orderBy: 'date ASC');
    }
    return await db.query('shifts', orderBy: 'date ASC');
  }

  Future<Map<String, dynamic>?> getShiftForDate(String date) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'shifts',
      where: 'date = ?',
      whereArgs: [date],
    );
    
    if (maps.isEmpty) return null;
    return maps[0];
  }

  Future<List<Map<String, dynamic>>> getUpcomingShifts(int days) async {
    final db = await database;
    final today = DateTime.now();
    final endDate = today.add(Duration(days: days));
    
    final List<Map<String, dynamic>> maps = await db.query(
      'shifts',
      where: 'date >= ? AND date <= ?',
      whereArgs: [
        today.toIso8601String().split('T')[0],
        endDate.toIso8601String().split('T')[0],
      ],
      orderBy: 'date ASC',
    );
    
    return maps;
  }

  Future<Map<String, int>> getShiftStatistics(String month, {String? rosterMonth}) async {
    final db = await database;
    
    // Get all shifts for the month
    List<Map<String, dynamic>> maps;
    if (rosterMonth != null) {
      maps = await db.query(
        'shifts',
        where: 'roster_month = ? AND date LIKE ?',
        whereArgs: [rosterMonth, '$month%'],
      );
    } else {
      maps = await db.query(
        'shifts',
        where: 'date LIKE ?',
        whereArgs: ['$month%'],
      );
    }
    
    int morningCount = 0;
    int afternoonCount = 0;
    int nightCount = 0;
    int weekOffCount = 0;
    
    for (var shift in maps) {
      switch (shift['shift_type']) {
        case 'morning':
          morningCount++;
          break;
        case 'afternoon':
          afternoonCount++;
          break;
        case 'night':
          nightCount++;
          break;
        case 'week_off':
          weekOffCount++;
          break;
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

  Future<void> clearAllShifts({String? rosterMonth}) async {
    final db = await database;
    if (rosterMonth != null) {
      await db.delete('shifts', where: 'roster_month = ?', whereArgs: [rosterMonth]);
      await db.delete('shift_metadata', where: 'roster_month = ?', whereArgs: [rosterMonth]);
    } else {
      await db.delete('shifts');
      await db.delete('shift_metadata');
    }
  }
  
  // Get list of available roster months
  Future<List<String>> getAvailableRosterMonths() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.rawQuery(
      'SELECT DISTINCT roster_month FROM shifts WHERE roster_month IS NOT NULL ORDER BY roster_month DESC'
    );
    return maps.map((m) => m['roster_month'] as String).toList();
  }
}
