import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'dart:convert';

import 'storage_service.dart';
import 'app_init_service.dart';
import '../models/task.dart';
import '../models/note.dart';
import '../models/daily_reminder.dart';
import '../models/shift.dart';
import 'notification_service.dart';
import 'pb_debug_logger.dart';

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

  String? _getUserId() {
    if (pb.authStore.record != null) return pb.authStore.record!.id;
    final token = pb.authStore.token;
    if (token.isEmpty) return null;
    try {
      final parts = token.split('.');
      if (parts.length == 3) {
        final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
        return payload['id'];
      }
    } catch (_) {}
    return null;
  }

  Future<void> syncAll() async {
    if (pb.authStore.token.isEmpty) return;

    pbLog('🔄 Starting Sync...');
    await syncDeletions();
    await syncTasks();
    await syncNotes();
    await syncDailyReminders();
    await syncChecklists();
    await syncShiftsData();
    await syncGoldPrices();
    
    // Update last sync time
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncKey, DateTime.now().toUtc().toIso8601String());
    pbLog('✅ Sync Complete');
    
    // Ensure alarms are re-validated after syncing
    try {
      await AppInitService().initialize();
    } catch(e) {
      pbLog('⚠️ Failed to initialize AppInitService after sync: $e');
    }
  }

  // --- Deletions ---
  Future<void> syncDeletions() async {
      try {
          final db = await storage.database;
          // Verify table exists just in case
          final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='deleted_records'");
          if (tables.isEmpty) return;

          final deletedRecords = await db.query('deleted_records');
          if (deletedRecords.isNotEmpty) pbLog('  🗑️ Processing ${deletedRecords.length} deletions...');
          
          for (var row in deletedRecords) {
              final remoteId = row['remoteId'] as String;
              final collection = row['collectionName'] as String;
              try {
                  await pb.collection(collection).delete(remoteId);
                  pbLog('  ✅ Deleted $remoteId from $collection');
                  await db.delete('deleted_records', where: 'id = ?', whereArgs: [row['id']]);
              } catch (e) {
                 if (e.toString().contains('404')) {
                    await db.delete('deleted_records', where: 'id = ?', whereArgs: [row['id']]);
                 } else {
                    pbLog('  ❌ Error deleting $remoteId from $collection: $e');
                 }
              }
          }
      } catch (e) {
          pbLog('  ❌ Error syncing deletions: $e');
      }
  }

  // --- Tasks ---

  Future<void> syncTasks() async {
    // Migrated fully to Firebase Firestore.
    // SQFlite sync logic deleted.
  }

  // --- Notes ---

  Future<void> syncNotes() async {
    // Migrated fully to Firebase Firestore.
    // SQFlite sync logic deleted.
  }

  // --- Daily Reminders ---
  
  Future<void> syncDailyReminders() async {
    // Migrated fully to Firebase Firestore.
    // SQFlite sync logic deleted.
  }

  // --- Checklists ---
  
  Future<void> syncChecklists() async {
    if (_syncingChecklists) return;
    _syncingChecklists = true;
    try {
      final db = await storage.database;
      final userId = _getUserId(); // Changed from user = pb.authStore.model
      if (userId == null) return;

    // --- 1. Sync Checklists ---
    
    // a. Push local changes
    final dirtyChecklists = await db.query('checklists', where: 'isSynced = 0');
    if (dirtyChecklists.isNotEmpty) pbLog('  📤 Pushing ${dirtyChecklists.length} checklists...');

    for (var row in dirtyChecklists) {
      String? remoteId = row['remoteId'] as String?;
      try {
        final body = {
          'title': row['title'],
          'icon_code': row['iconCode'],
          'color': row['color'],
          'user': userId,
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
        pbLog('  ❌ Error pushing checklist ${row['id']}: $e');
      }
    }
    
    // b. Pull remote changes
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getString(_lastSyncKey) ?? '2000-01-01 00:00:00.000Z';
    
    try {
      final resultList = await pb.collection('checklists').getList(
        filter: 'updated > "$lastSync"',
      );
      
      if (resultList.items.isNotEmpty) pbLog('  📥 Pulling ${resultList.items.length} checklists...');

      for (var record in resultList.items) {
        final local = await db.query('checklists', where: 'remoteId = ?', whereArgs: [record.id]);
        
        final listData = {
          'title': record.data['title'],
          'iconCode': record.data['icon_code'],
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
       pbLog('  ❌ Error pulling checklists: $e');
    }

    // --- 2. Sync Checklist Items ---
    
    // a. Push local item changes
    final dirtyItems = await db.query('checklist_items', where: 'isSynced = 0');
    if (dirtyItems.isNotEmpty) pbLog('  📤 Pushing ${dirtyItems.length} checklist items...');

    for (var row in dirtyItems) {
      String? remoteId = row['remoteId'] as String?;
      int localChecklistId = row['checklistId'] as int;
      
      // We must get the remoteId of the parent checklist to link in PocketBase
      final parentList = await db.query('checklists', where: 'id = ?', whereArgs: [localChecklistId]);
      if (parentList.isEmpty || parentList.first['remoteId'] == null || parentList.first['remoteId'].toString().isEmpty) {
        // Skip syncing if parent checklist is not synced yet (edge case)
        continue;
      }
      String parentRemoteId = parentList.first['remoteId'] as String;

      try {
        final body = {
          'checklist': parentRemoteId,
          'text': row['text'],
          'is_checked': row['isChecked'] == 1,
          'user': userId,
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
        pbLog('  ❌ Error pushing checklist item ${row['id']}: $e');
      }
    }
    
    // b. Pull remote item changes
    try {
      final itemList = await pb.collection('checklist_items').getList(
        filter: 'updated > "$lastSync"',
      );
      
      if (itemList.items.isNotEmpty) pbLog('  📥 Pulling ${itemList.items.length} checklist items...');

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
         pbLog('  ❌ Error pulling checklist items: $e');
      }
    } finally {
       _syncingChecklists = false;
    }
  }

  // --- Shifts Data ---
  
  Future<void> syncShiftsData() async {
    if (_syncingShifts) return;
    _syncingShifts = true;
    try {
      final db = await storage.database;
      final userId = _getUserId();
      if (userId == null) return;
      
      final dirtyData = await db.query('shifts_data', where: 'isSynced = 0');
      if (dirtyData.isNotEmpty) pbLog('  📤 Pushing ${dirtyData.length} shifts data...');
      
      for (var row in dirtyData) {
        String? remoteId = row['remoteId'] as String?;
        final body = {
          'month_year': row['month_year'],
          'json_data': row['json_data'],
          'user': userId,
        };
        try {
          if (remoteId == null || remoteId.isEmpty) {
            final record = await pb.collection('shifts_data').create(body: body);
            await db.update('shifts_data', {
              'remoteId': record.id, 'isSynced': 1, 'updatedAt': record.updated,
            }, where: 'month_year = ?', whereArgs: [row['month_year']]);
          } else {
            await pb.collection('shifts_data').update(remoteId, body: body);
            await db.update('shifts_data', {
              'isSynced': 1, 'updatedAt': DateTime.now().toIso8601String(),
            }, where: 'month_year = ?', whereArgs: [row['month_year']]);
          }
        } catch (e) {
          pbLog('  ❌ Error pushing shifts data ${row['month_year']}: $e');
        }
      }
      
      final prefs = await SharedPreferences.getInstance();
      final lastSync = prefs.getString(_lastSyncKey) ?? '2000-01-01 00:00:00.000Z';
      
      try {
        final metaList = await pb.collection('shifts_data').getList(filter: 'updated > "$lastSync"');
        if (metaList.items.isNotEmpty) pbLog('  📥 Pulling ${metaList.items.length} shifts data...');
        for (var record in metaList.items) {
          final local = await db.query('shifts_data', where: 'remoteId = ?', whereArgs: [record.id]);
          final metaData = {
            'month_year': record.data['month_year'],
            'json_data': record.data['json_data'],
            'remoteId': record.id, 'isSynced': 1, 'updatedAt': record.updated,
          };
          if (local.isEmpty) {
             final existing = await db.query('shifts_data', where: 'month_year = ?', whereArgs: [record.data['month_year']]);
             if (existing.isNotEmpty) {
                 await db.update('shifts_data', metaData, where: 'month_year = ?', whereArgs: [existing.first['month_year']]);
             } else {
                 await db.insert('shifts_data', metaData);
             }
          } else {
            await db.update('shifts_data', metaData, where: 'remoteId = ?', whereArgs: [record.id]);
          }
          
          try {
             final rawJson = record.data['json_data'];
             final jsonData = json.decode(rawJson as String);
             final roster = ShiftRoster.fromJson(jsonData);
             final shiftsToSave = roster.shifts.map((s) => s.toMap()).toList();
             
             await storage.saveShiftRoster(
                roster.employeeName,
                record.data['month_year'] as String,
                shiftsToSave,
                rosterMonth: record.data['month_year'] as String,
                rawJson: rawJson as String,
                skipSyncFlag: true
             );
          } catch(e) {
             print("Failed to auto-parse pulled shift data JSON: $e");
          }
        }
      } catch (e) {
         pbLog('  ❌ Error pulling shifts data: $e');
      }
    } catch (e) {
        pbLog('  ❌ Error in syncShiftsData: $e');
    } finally {
        _syncingShifts = false;
    }
  }
  Future<void> syncGoldPrices() async {
    final userId = _getUserId();
    if (userId == null) return;
    
    try {
      final db = await storage.database;
      
      // 1. Push Local Changes
      final unsynced = await db.query('gold_prices', where: 'isSynced = 0');
      if (unsynced.isNotEmpty) pbLog('  ⬆️ Pushing ${unsynced.length} gold prices...');
      
      for (var row in unsynced) {
        final remoteId = row['remoteId'] as String?;
        try {
          final body = {
            'date': row['date'],
            'timestamp': row['timestamp'],
            'price': row['price'],
            'priceChange': row['priceChange'],
            'user': userId,
          };
          
          if (remoteId == null || remoteId.isEmpty) {
            // Check if it exists by date first, maybe pulled from another device
            final existingList = await pb.collection('gold_prices').getList(
              filter: 'date = "${row['date']}" && user = "$userId"',
              perPage: 1
            );
            
            if (existingList.items.isNotEmpty) {
              final record = await pb.collection('gold_prices').update(existingList.items.first.id, body: body);
              await db.update('gold_prices', {
                'remoteId': record.id,
                'isSynced': 1,
                'updatedAt': record.updated,
              }, where: 'date = ?', whereArgs: [row['date']]);
            } else {
              final record = await pb.collection('gold_prices').create(body: body);
              await db.update('gold_prices', {
                'remoteId': record.id,
                'isSynced': 1,
                'updatedAt': record.updated,
              }, where: 'date = ?', whereArgs: [row['date']]);
            }
          } else {
            await pb.collection('gold_prices').update(remoteId, body: body);
            await db.update('gold_prices', {
              'isSynced': 1,
              'updatedAt': DateTime.now().toIso8601String(),
            }, where: 'remoteId = ?', whereArgs: [remoteId]);
          }
        } catch (e) {
          pbLog('  ❌ Error pushing gold price for ${row['date']}: $e');
        }
      }
      
      // 2. Pull Remote Changes
      final prefs = await SharedPreferences.getInstance();
      final lastSync = prefs.getString(_lastSyncKey) ?? '2000-01-01 00:00:00.000Z';
      
      try {
        final recordsList = await pb.collection('gold_prices').getList(
          filter: 'updated > "$lastSync"',
          perPage: 500, // Fetch up to 500
        );
        
        if (recordsList.items.isNotEmpty) pbLog('  📥 Pulling ${recordsList.items.length} gold prices...');
        
        for (var record in recordsList.items) {
          final dateStr = record.data['date'] as String;
          final local = await db.query('gold_prices', where: 'date = ?', whereArgs: [dateStr]);
          
          final map = {
            'date': dateStr,
            'timestamp': record.data['timestamp'],
            'price': (record.data['price'] as num).toDouble(),
            'priceChange': (record.data['priceChange'] as num).toDouble(),
            'remoteId': record.id,
            'isSynced': 1,
            'updatedAt': record.updated,
          };
          
          if (local.isEmpty) {
            await db.insert('gold_prices', map, conflictAlgorithm: ConflictAlgorithm.replace);
          } else {
            await db.update('gold_prices', map, where: 'date = ?', whereArgs: [dateStr]);
          }
        }
      } catch (e) {
         pbLog('  ❌ Error pulling gold prices: $e');
      }
    } catch (e) {
      pbLog('  ❌ Error in syncGoldPrices: $e');
    }
  }
}

