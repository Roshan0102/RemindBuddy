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
        version: 6,
        onCreate: (db, version) async {
          await _createTables(db);
        },
      );
    }
    
    // For mobile, use persistent database
    String path = join(await getDatabasesPath(), 'remindbuddy.db');
    return await openDatabase(
      path,
      version: 6, 
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'CREATE TABLE notes(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, content TEXT, date TEXT, isLocked INTEGER)',
          );
        }
        if (oldVersion < 3) {
           try {
             await db.execute('ALTER TABLE tasks ADD COLUMN isAnnoying INTEGER DEFAULT 0');
           } catch (e) { print("Column isAnnoying might already exist"); }
           try {
             await db.execute('ALTER TABLE notes ADD COLUMN isLocked INTEGER DEFAULT 0');
           } catch (e) { print("Column isLocked might already exist"); }
        }
        if (oldVersion < 4) {
          try {
            await db.execute(
              'CREATE TABLE daily_reminders(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, description TEXT, time TEXT, isActive INTEGER, isAnnoying INTEGER)',
            );
          } catch (e) { print("Table daily_reminders might already exist"); }
        }
        if (oldVersion < 5) {
          try {
            await db.execute(
              'CREATE TABLE gold_prices(date TEXT PRIMARY KEY, price22k REAL, price24k REAL, city TEXT)',
            );
          } catch (e) { print("Table gold_prices might already exist"); }
        }
        if (oldVersion < 6) {
           // Add Checklists tables
           try {
             await db.execute(
               'CREATE TABLE checklists(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, iconCode INTEGER, color INTEGER)',
             );
             await db.execute(
               'CREATE TABLE checklist_items(id INTEGER PRIMARY KEY AUTOINCREMENT, checklistId INTEGER, text TEXT, isChecked INTEGER)',
             );
           } catch (e) { print("Checklist tables might already exist"); }

           // Migrate Gold Price table to support datetime (multiple entries per day) if needed
           // For simplicity, we'll just keep adding to it, but the primary key logic in code will change to use full timestamp or unique ID
           // Dropping and recreating is risky for data loss, so we'll just create a new one if it doesn't exist or modify logic
           // To support multiple updates per day, the PRIMARY KEY on 'date' (YYYY-MM-DD) is problematic.
           // Let's CREATE a new table "gold_prices_v2" with a proper ID or allow multiple dates
           try {
             await db.execute(
               'CREATE TABLE gold_prices_history(id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TEXT, price22k REAL, price24k REAL, city TEXT)',
             );
             // Migrate old data
             // await db.execute('INSERT INTO gold_prices_history (timestamp, price22k, price24k, city) SELECT date, price22k, price24k, city FROM gold_prices');
           } catch (e) { print("gold_prices_history table error: $e"); }
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
}
