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
        version: 5,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE tasks(id INTEGER PRIMARY KEY, title TEXT, description TEXT, date TEXT, time TEXT, repeat TEXT, isAnnoying INTEGER)',
          );
          await db.execute(
            'CREATE TABLE notes(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, content TEXT, date TEXT, isLocked INTEGER)',
          );
          await db.execute(
            'CREATE TABLE daily_reminders(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, description TEXT, time TEXT, isActive INTEGER, isAnnoying INTEGER)',
          );
          await db.execute(
            'CREATE TABLE gold_prices(date TEXT PRIMARY KEY, price22k REAL, price24k REAL, city TEXT)',
          );
        },
      );
    }
    
    // For mobile, use persistent database
    String path = join(await getDatabasesPath(), 'remindbuddy.db');
    return await openDatabase(
      path,
      version: 5, // Increment version for gold_prices table
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE tasks(id INTEGER PRIMARY KEY, title TEXT, description TEXT, date TEXT, time TEXT, repeat TEXT, isAnnoying INTEGER)',
        );
        await db.execute(
          'CREATE TABLE notes(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, content TEXT, date TEXT, isLocked INTEGER)',
        );
        await db.execute(
          'CREATE TABLE daily_reminders(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, description TEXT, time TEXT, isActive INTEGER, isAnnoying INTEGER)',
        );
        await db.execute(
          'CREATE TABLE gold_prices(date TEXT PRIMARY KEY, price22k REAL, price24k REAL, city TEXT)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'CREATE TABLE notes(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, content TEXT, date TEXT, isLocked INTEGER)',
          );
        }
        if (oldVersion < 3) {
           // Add new columns if they don't exist
           try {
             await db.execute('ALTER TABLE tasks ADD COLUMN isAnnoying INTEGER DEFAULT 0');
           } catch (e) { print("Column isAnnoying might already exist"); }
           
           try {
             await db.execute('ALTER TABLE notes ADD COLUMN isLocked INTEGER DEFAULT 0');
           } catch (e) { print("Column isLocked might already exist"); }
        }
        if (oldVersion < 4) {
          // Add daily_reminders table
          try {
            await db.execute(
              'CREATE TABLE daily_reminders(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, description TEXT, time TEXT, isActive INTEGER, isAnnoying INTEGER)',
            );
          } catch (e) { print("Table daily_reminders might already exist"); }
        }
        if (oldVersion < 5) {
          // Add gold_prices table
          try {
            await db.execute(
              'CREATE TABLE gold_prices(date TEXT PRIMARY KEY, price22k REAL, price24k REAL, city TEXT)',
            );
          } catch (e) { print("Table gold_prices might already exist"); }
        }
      },
    );
  }

  // ... Task methods ...

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

  Future<void> deleteNote(int id) async {
    final db = await database;
    await db.delete(
      'notes',
      where: 'id = ?',
      whereArgs: [id],
    );
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

  Future<void> clearOldTasks(String today) async {
    final db = await database;
    // Simple logic: delete tasks where date < today
    // Note: String comparison works for YYYY-MM-DD format
    await db.delete('tasks', where: 'date < ?', whereArgs: [today]);
  }

  Future<void> deleteTask(int id) async {
    final db = await database;
    await db.delete(
      'tasks',
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

  // Gold Price Methods
  Future<void> saveGoldPrice(GoldPrice price) async {
    final db = await database;
    await db.insert(
      'gold_prices',
      price.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<GoldPrice>> getGoldPrices({int limit = 10}) async {
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
      'gold_prices',
      orderBy: 'date DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return GoldPrice.fromJson(maps[0]);
  }

  Future<void> deleteOldGoldPrices(int daysToKeep) async {
    final db = await database;
    final cutoffDate = DateTime.now().subtract(Duration(days: daysToKeep));
    final cutoffDateStr = cutoffDate.toIso8601String().split('T')[0];
    await db.delete(
      'gold_prices',
      where: 'date < ?',
      whereArgs: [cutoffDateStr],
    );
  }
}
