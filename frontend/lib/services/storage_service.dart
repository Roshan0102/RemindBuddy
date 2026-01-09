import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/task.dart';

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
    String path = join(await getDatabasesPath(), 'remindbuddy.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) {
        return db.execute(
          'CREATE TABLE tasks(id INTEGER PRIMARY KEY, title TEXT, description TEXT, date TEXT, time TEXT, repeat TEXT)',
        );
      },
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
}
