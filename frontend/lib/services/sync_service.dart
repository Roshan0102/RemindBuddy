import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:convert';

import 'storage_service.dart';
import '../models/task.dart';
import '../models/note.dart';
import '../models/daily_reminder.dart';
import '../models/shift.dart';
import 'notification_service.dart';

class SyncService {
  final PocketBase pb;
  final StorageService storage = StorageService();
  
  static const String _lastSyncKey = 'last_sync_time';

  // Locks to prevent concurrent sync operations
  static bool _syncingTasks = false;
  static bool _syncingNotes = false;
  static bool _syncingDaily = false;
  static bool _syncingChecklists = false;
  static bool _syncingShifts = false;

  SyncService(this.pb);

  Future<void> syncAll() async {
    if (pb.authStore.model == null) return;

    print('🔄 Starting Sync...');
    await syncTasks();
    await syncNotes();
    await syncDailyReminders();
    await syncChecklists();
    await syncShifts();
    
    // Update last sync time
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncKey, DateTime.now().toUtc().toIso8601String());
    print('✅ Sync Complete');
  }

  // --- Tasks ---

  Future<void> syncTasks() async {
    if (_syncingTasks) return;
    _syncingTasks = true;
    try {
      final db = await storage.database;
      final user = pb.authStore.model;
      if (user == null) return;
      
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
            int insertedId = await db.insert('tasks', taskData);
            taskData['id'] = insertedId;
            NotificationService().scheduleTaskNotification(Task.fromJson(taskData));
          } else {
            await db.update('tasks', taskData, where: 'remoteId = ?', whereArgs: [record.id]);
            taskData['id'] = local.first['id'];
            NotificationService().scheduleTaskNotification(Task.fromJson(taskData));
          }
        }
      } catch (e) {
         print('  ❌ Error pulling tasks: $e');
      }
    } finally {
      _syncingTasks = false;
    }
  }

  // --- Notes ---

  Future<void> syncNotes() async {
    if (_syncingNotes) return;
    _syncingNotes = true;
    try {
      final db = await storage.database;
      final user = pb.authStore.model;
      if (user == null) return;

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
    } finally {
       _syncingNotes = false;
    }
  }

  // --- Daily Reminders ---
  
  Future<void> syncDailyReminders() async {
    if (_syncingDaily) return;
    _syncingDaily = true;
    try {
      final db = await storage.database;
      final user = pb.authStore.model;
      if (user == null) return;

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
          int insertedId = await db.insert('daily_reminders', drData);
          drData['id'] = insertedId;
          if (drData['isActive'] == 1) {
            NotificationService().scheduleDailyReminder(DailyReminder.fromJson(drData));
          }
        } else {
          await db.update('daily_reminders', drData, where: 'remoteId = ?', whereArgs: [record.id]);
          drData['id'] = local.first['id'];
          if (drData['isActive'] == 1) {
            NotificationService().scheduleDailyReminder(DailyReminder.fromJson(drData));
          } else {
             NotificationService().cancelNotification((drData['id'] as int) + 100000); // 100000 is the daily reminder offset
          }
        }
      }
      } catch (e) {
         print('  ❌ Error pulling daily reminders: $e');
      }
    } finally {
       _syncingDaily = false;
    }
  }

  // --- Checklists ---
  
  Future<void> syncChecklists() async {
    if (_syncingChecklists) return;
    _syncingChecklists = true;
    try {
      final db = await storage.database;
      final user = pb.authStore.model;
      if (user == null) return;

    // --- 1. Sync Checklists ---
    
    // a. Push local changes
    final dirtyChecklists = await db.query('checklists', where: 'isSynced = 0');
    if (dirtyChecklists.isNotEmpty) print('  📤 Pushing ${dirtyChecklists.length} checklists...');

    for (var row in dirtyChecklists) {
      String? remoteId = row['remoteId'] as String?;
      try {
        final body = {
          'title': row['title'],
          'iconCode': row['iconCode'],
          'color': row['color'],
          'user': user.id,
        };
        
        if (remoteId == null || remoteId.isEmpty) {
           final record = await pb.collection('checklists').create(body: body);
           remoteId = record.id;
           await db.update('checklists', {
             'remoteId': record.id,
             'isSynced': 1,
             'updatedAt': record.updated,
           }, where: 'id = ?', whereArgs: [row['id']]);
        } else {
           await pb.collection('checklists').update(remoteId, body: body);
           await db.update('checklists', {
             'isSynced': 1,
             'updatedAt': DateTime.now().toIso8601String(),
           }, where: 'id = ?', whereArgs: [row['id']]);
        }
      } catch (e) {
        print('  ❌ Error pushing checklist ${row['id']}: $e');
      }
    }
    
    // b. Pull remote changes
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getString(_lastSyncKey) ?? '2000-01-01 00:00:00.000Z';
    
    try {
      final resultList = await pb.collection('checklists').getList(
        filter: 'updated > "$lastSync"',
      );
      
      if (resultList.items.isNotEmpty) print('  📥 Pulling ${resultList.items.length} checklists...');

      for (var record in resultList.items) {
        final local = await db.query('checklists', where: 'remoteId = ?', whereArgs: [record.id]);
        
        final listData = {
          'title': record.data['title'],
          'iconCode': record.data['iconCode'],
          'color': record.data['color'],
          'remoteId': record.id,
          'isSynced': 1,
          'updatedAt': record.updated,
        };

        if (local.isEmpty) {
          await db.insert('checklists', listData);
        } else {
          await db.update('checklists', listData, where: 'remoteId = ?', whereArgs: [record.id]);
        }
      }
    } catch (e) {
       print('  ❌ Error pulling checklists: $e');
    }

    // --- 2. Sync Checklist Items ---
    
    // a. Push local item changes
    final dirtyItems = await db.query('checklist_items', where: 'isSynced = 0');
    if (dirtyItems.isNotEmpty) print('  📤 Pushing ${dirtyItems.length} checklist items...');

    for (var row in dirtyItems) {
      String? remoteId = row['remoteId'] as String?;
      int localChecklistId = row['checklistId'] as int;
      
      // We must get the remoteId of the parent checklist to link in PocketBase
      final parentList = await db.query('checklists', where: 'id = ?', whereArgs: [localChecklistId]);
      if (parentList.isEmpty || parentList.first['remoteId'] == null) {
        // Skip syncing if parent checklist is not synced yet (edge case)
        continue;
      }
      String parentRemoteId = parentList.first['remoteId'] as String;

      try {
        final body = {
          'checklist': parentRemoteId,
          'text': row['text'],
          'is_checked': row['isChecked'] == 1,
        };
        
        if (remoteId == null || remoteId.isEmpty) {
           final record = await pb.collection('checklist_items').create(body: body);
           await db.update('checklist_items', {
             'remoteId': record.id,
             'isSynced': 1,
             'updatedAt': record.updated,
           }, where: 'id = ?', whereArgs: [row['id']]);
        } else {
           await pb.collection('checklist_items').update(remoteId, body: body);
           await db.update('checklist_items', {
             'isSynced': 1,
             'updatedAt': DateTime.now().toIso8601String(),
           }, where: 'id = ?', whereArgs: [row['id']]);
        }
      } catch (e) {
        print('  ❌ Error pushing checklist item ${row['id']}: $e');
      }
    }
    
    // b. Pull remote item changes
    try {
      final itemList = await pb.collection('checklist_items').getList(
        filter: 'updated > "$lastSync"',
      );
      
      if (itemList.items.isNotEmpty) print('  📥 Pulling ${itemList.items.length} checklist items...');

      for (var record in itemList.items) {
        // Find local parent by parent remoteId
        final parentRemoteId = record.data['checklist'];
        final parentList = await db.query('checklists', where: 'remoteId = ?', whereArgs: [parentRemoteId]);
        
        if (parentList.isEmpty) continue; // Parent not here, skip
        
        int parentLocalId = parentList.first['id'] as int;
        
        final local = await db.query('checklist_items', where: 'remoteId = ?', whereArgs: [record.id]);
        
        final itemData = {
          'checklistId': parentLocalId,
          'text': record.data['text'],
          'isChecked': record.data['is_checked'] == true ? 1 : 0,
          'remoteId': record.id,
          'isSynced': 1,
          'updatedAt': record.updated,
        };

        if (local.isEmpty) {
          await db.insert('checklist_items', itemData);
        } else {
          await db.update('checklist_items', itemData, where: 'remoteId = ?', whereArgs: [record.id]);
        }
      }
      } catch (e) {
         print('  ❌ Error pulling checklist items: $e');
      }
    } finally {
       _syncingChecklists = false;
    }
  }

  // --- Shifts ---
  
  Future<void> syncShifts() async {
    if (_syncingShifts) return;
    _syncingShifts = true;
    try {
      final db = await storage.database;
      final user = pb.authStore.model;
      if (user == null) return;
      
      // --- 1. Push Metadata ---
      final dirtyMetadata = await db.query('shift_metadata', where: 'isSynced = 0');
      if (dirtyMetadata.isNotEmpty) print('  📤 Pushing ${dirtyMetadata.length} shift metadata...');
      for (var row in dirtyMetadata) {
        String? remoteId = row['remoteId'] as String?;
        final body = {
          'employee_name': row['employee_name'],
          'month': row['month'],
          'roster_month': row['roster_month'],
          'user': user.id,
        };
        try {
          if (remoteId == null || remoteId.isEmpty) {
            final record = await pb.collection('shift_metadata').create(body: body);
            await db.update('shift_metadata', {
              'remoteId': record.id, 'isSynced': 1, 'updatedAt': record.updated,
            }, where: 'id = ?', whereArgs: [row['id']]);
          } else {
            await pb.collection('shift_metadata').update(remoteId, body: body);
            await db.update('shift_metadata', {
              'isSynced': 1, 'updatedAt': DateTime.now().toIso8601String(),
            }, where: 'id = ?', whereArgs: [row['id']]);
          }
        } catch (e) {
          print('  ❌ Error pushing shift_metadata: $e');
        }
      }

      // --- 2. Push Shifts ---
      final dirtyShifts = await db.query('shifts', where: 'isSynced = 0');
      if (dirtyShifts.isNotEmpty) print('  📤 Pushing ${dirtyShifts.length} shifts...');
      for (var row in dirtyShifts) {
        String? remoteId = row['remoteId'] as String?;
        final body = {
          'date': row['date'],
          'shift_type': row['shift_type'],
          'start_time': row['start_time'],
          'end_time': row['end_time'],
          'is_week_off': row['is_week_off'] == 1,
          'roster_month': row['roster_month'],
          'user': user.id,
        };
        try {
          if (remoteId == null || remoteId.isEmpty) {
            final record = await pb.collection('shifts').create(body: body);
            await db.update('shifts', {
              'remoteId': record.id, 'isSynced': 1, 'updatedAt': record.updated,
            }, where: 'id = ?', whereArgs: [row['id']]);
          } else {
            await pb.collection('shifts').update(remoteId, body: body);
            await db.update('shifts', {
              'isSynced': 1, 'updatedAt': DateTime.now().toIso8601String(),
            }, where: 'id = ?', whereArgs: [row['id']]);
          }
        } catch (e) {
          print('  ❌ Error pushing shift ${row['date']}: $e');
        }
      }

      // --- 3. Pull Content ---
      final prefs = await SharedPreferences.getInstance();
      final lastSync = prefs.getString(_lastSyncKey) ?? '2000-01-01 00:00:00.000Z';
      
      // Pull Metadata
      try {
        final metaList = await pb.collection('shift_metadata').getList(filter: 'updated > "$lastSync"');
        for (var record in metaList.items) {
          final local = await db.query('shift_metadata', where: 'remoteId = ?', whereArgs: [record.id]);
          final metaData = {
            'employee_name': record.data['employee_name'],
            'month': record.data['month'],
            'roster_month': record.data['roster_month'],
            'remoteId': record.id, 'isSynced': 1, 'updatedAt': record.updated,
          };
          if (local.isEmpty) {
             final existing = await db.query('shift_metadata', where: 'roster_month = ?', whereArgs: [record.data['roster_month']]);
             if (existing.isNotEmpty) {
                 await db.update('shift_metadata', metaData, where: 'id = ?', whereArgs: [existing.first['id']]);
             } else {
                 await db.insert('shift_metadata', metaData);
             }
          } else {
            await db.update('shift_metadata', metaData, where: 'remoteId = ?', whereArgs: [record.id]);
          }
        }
      } catch (e) {}

      // Pull Shifts
      try {
        final resultList = await pb.collection('shifts').getList(filter: 'updated > "$lastSync"', perPage: 500);
        if (resultList.items.isNotEmpty) print('  📥 Pulling ${resultList.items.length} shifts...');

        for (var record in resultList.items) {
          final local = await db.query('shifts', where: 'remoteId = ?', whereArgs: [record.id]);
          
          final shiftData = {
            'date': record.data['date'],
            'shift_type': record.data['shift_type'],
            'start_time': record.data['start_time'],
            'end_time': record.data['end_time'],
            'is_week_off': record.data['is_week_off'] == true ? 1 : 0,
            'roster_month': record.data['roster_month'],
            'remoteId': record.id,
            'isSynced': 1,
            'updatedAt': record.updated,
          };
          
          if (local.isEmpty) {
             final existingByDate = await db.query('shifts', where: 'date = ?', whereArgs: [record.data['date']]);
             if (existingByDate.isNotEmpty) {
                 await db.update('shifts', shiftData, where: 'id = ?', whereArgs: [existingByDate.first['id']]);
             } else {
                 await db.insert('shifts', shiftData);
             }
          } else {
             await db.update('shifts', shiftData, where: 'remoteId = ?', whereArgs: [record.id]);
          }
        }
      } catch (e) {
         print('  ❌ Error pulling shifts: $e');
      }
    } finally {
       _syncingShifts = false;
    }
  }
}
