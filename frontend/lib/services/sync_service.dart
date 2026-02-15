import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'storage_service.dart';
import '../models/task.dart';
import '../models/note.dart';
import '../models/daily_reminder.dart';

class SyncService {
  final PocketBase pb;
  final StorageService storage = StorageService();
  
  static const String _lastSyncKey = 'last_sync_time';

  SyncService(this.pb);

  Future<void> syncAll() async {
    if (pb.authStore.model == null) return;

    print('🔄 Starting Sync...');
    await syncTasks();
    await syncNotes();
    await syncDailyReminders();
    // await syncChecklists(); // TODO
    // await syncShifts(); // TODO
    
    // Update last sync time
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncKey, DateTime.now().toUtc().toIso8601String());
    print('✅ Sync Complete');
  }

  // --- Tasks ---

  Future<void> syncTasks() async {
    final db = await storage.database;
    final user = pb.authStore.model;
    
    // 1. Push Local Changes
    final dirtyTasks = await db.query('tasks', where: 'isSynced = 0');
    if (dirtyTasks.isNotEmpty) print('  📤 Pushing ${dirtyTasks.length} tasks...');
    
    for (var row in dirtyTasks) {
      Task task = Task.fromJson(row);
      try {
        final body = {
          'title': task.title,
          'description': task.description,
          'date': task.date,
          'time': task.time,
          'repeat': task.repeat,
          'is_annoying': task.isAnnoying,
          'user': user.id,
        };

        if (task.remoteId == null || task.remoteId!.isEmpty) {
          // Create
          final record = await pb.collection('tasks').create(body: body);
          await db.update('tasks', {
             'remoteId': record.id,
             'isSynced': 1,
             'updatedAt': record.updated,
          }, where: 'id = ?', whereArgs: [task.id]);
        } else {
          // Update
          await pb.collection('tasks').update(task.remoteId!, body: body);
          await db.update('tasks', {
             'isSynced': 1,
             'updatedAt': DateTime.now().toIso8601String(),
          }, where: 'id = ?', whereArgs: [task.id]);
        }
      } catch (e) {
        print('  ❌ Error pushing task ${task.id}: $e');
      }
    }

    // 2. Pull Remote Changes
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getString(_lastSyncKey) ?? '2000-01-01 00:00:00.000Z';
    
    try {
      final resultList = await pb.collection('tasks').getList(
        filter: 'updated > "$lastSync"',
      );
      
      if (resultList.items.isNotEmpty) print('  📥 Pulling ${resultList.items.length} tasks...');

      for (var record in resultList.items) {
        // Check if exists locally by remoteId
        final local = await db.query('tasks', where: 'remoteId = ?', whereArgs: [record.id]);
        
        final taskData = {
          'title': record.data['title'],
          'description': record.data['description'],
          'date': record.data['date'],
          'time': record.data['time'],
          'repeat': record.data['repeat'],
          'isAnnoying': record.data['is_annoying'] == true ? 1 : 0,
          'remoteId': record.id,
          'isSynced': 1,
          'updatedAt': record.updated,
        };

        if (local.isEmpty) {
          await db.insert('tasks', taskData);
        } else {
          await db.update('tasks', taskData, where: 'remoteId = ?', whereArgs: [record.id]);
        }
      }
    } catch (e) {
       print('  ❌ Error pulling tasks: $e');
    }
  }

  // --- Notes ---

  Future<void> syncNotes() async {
    final db = await storage.database;
    final user = pb.authStore.model;

    // 1. Push
    final dirtyNotes = await db.query('notes', where: 'isSynced = 0');
    if (dirtyNotes.isNotEmpty) print('  📤 Pushing ${dirtyNotes.length} notes...');

    for (var row in dirtyNotes) {
      Note note = Note.fromMap(row);
      try {
        final body = {
          'title': note.title,
          'content': note.content,
          'date': note.date,
          'is_locked': note.isLocked,
          'user': user.id,
        };

        if (note.remoteId == null || note.remoteId!.isEmpty) {
           final record = await pb.collection('notes').create(body: body);
           await db.update('notes', {
             'remoteId': record.id,
             'isSynced': 1,
             'updatedAt': record.updated,
           }, where: 'id = ?', whereArgs: [note.id]);
        } else {
           await pb.collection('notes').update(note.remoteId!, body: body);
           await db.update('notes', {
             'isSynced': 1,
             'updatedAt': DateTime.now().toIso8601String(),
           }, where: 'id = ?', whereArgs: [note.id]);
        }
      } catch (e) {
        print('  ❌ Error pushing note ${note.id}: $e');
      }
    }
    
    // 2. Pull
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getString(_lastSyncKey) ?? '2000-01-01 00:00:00.000Z';
    
    try {
      final resultList = await pb.collection('notes').getList(
        filter: 'updated > "$lastSync"',
      );
      
      if (resultList.items.isNotEmpty) print('  📥 Pulling ${resultList.items.length} notes...');

      for (var record in resultList.items) {
        final local = await db.query('notes', where: 'remoteId = ?', whereArgs: [record.id]);
        
        final noteData = {
          'title': record.data['title'],
          'content': record.data['content'],
          'date': record.data['date'],
          'isLocked': record.data['is_locked'] == true ? 1 : 0,
          'remoteId': record.id,
          'isSynced': 1,
          'updatedAt': record.updated,
        };

        if (local.isEmpty) {
          await db.insert('notes', noteData);
        } else {
          await db.update('notes', noteData, where: 'remoteId = ?', whereArgs: [record.id]);
        }
      }
    } catch (e) {
       print('  ❌ Error pulling notes: $e');
    }
  }

  // --- Daily Reminders ---
  
  Future<void> syncDailyReminders() async {
    final db = await storage.database;
    final user = pb.authStore.model;

    // 1. Push
    final dirtyReminders = await db.query('daily_reminders', where: 'isSynced = 0');
    if (dirtyReminders.isNotEmpty) print('  📤 Pushing ${dirtyReminders.length} daily reminders...');

    for (var row in dirtyReminders) {
      // Create manual object if fromJson fails (but fromJson works for map)
      // DailyReminder.fromJson(row) works.
      String? remoteId = row['remoteId'] as String?;
      bool isActive = row['isActive'] == 1; // row is int
      bool isAnnoying = row['isAnnoying'] == 1;

      try {
        final body = {
          'title': row['title'],
          'description': row['description'],
          'time': row['time'],
          'is_active': isActive,
          'is_annoying': isAnnoying,
          'user': user.id,
        };
        
        if (remoteId == null || remoteId.isEmpty) {
           final record = await pb.collection('daily_reminders').create(body: body);
           await db.update('daily_reminders', {
             'remoteId': record.id,
             'isSynced': 1,
             'updatedAt': record.updated,
           }, where: 'id = ?', whereArgs: [row['id']]);
        } else {
           await pb.collection('daily_reminders').update(remoteId, body: body);
           await db.update('daily_reminders', {
             'isSynced': 1,
             'updatedAt': DateTime.now().toIso8601String(),
           }, where: 'id = ?', whereArgs: [row['id']]);
        }
      } catch (e) {
        print('  ❌ Error pushing daily reminder ${row['id']}: $e');
      }
    }
    
    // 2. Pull
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getString(_lastSyncKey) ?? '2000-01-01 00:00:00.000Z';
    
    try {
      final resultList = await pb.collection('daily_reminders').getList(
        filter: 'updated > "$lastSync"',
      );
      
      if (resultList.items.isNotEmpty) print('  📥 Pulling ${resultList.items.length} daily reminders...');

      for (var record in resultList.items) {
        final local = await db.query('daily_reminders', where: 'remoteId = ?', whereArgs: [record.id]);
        
        final drData = {
          'title': record.data['title'],
          'description': record.data['description'],
          'time': record.data['time'],
          'isActive': record.data['is_active'] == true ? 1 : 0,
          'isAnnoying': record.data['is_annoying'] == true ? 1 : 0,
          'remoteId': record.id,
          'isSynced': 1,
          'updatedAt': record.updated,
        };

        if (local.isEmpty) {
          await db.insert('daily_reminders', drData);
        } else {
          await db.update('daily_reminders', drData, where: 'remoteId = ?', whereArgs: [record.id]);
        }
      }
    } catch (e) {
       print('  ❌ Error pulling daily reminders: $e');
    }
  }
}
