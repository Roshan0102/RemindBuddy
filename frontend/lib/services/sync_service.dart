import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'storage_service.dart';
import 'app_init_service.dart';
import 'pb_debug_logger.dart';

class SyncService {
  final PocketBase pb;
  final StorageService storage = StorageService();
  
  static const String _lastSyncKey = 'last_sync_time';

  SyncService(this.pb);

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
    // Migrated fully to Firebase Firestore.
    // SQFlite sync logic deleted.
  }

  // --- Shifts Data ---
  
  Future<void> syncShiftsData() async {
    // Migrated fully to Firebase Firestore.
    // SQFlite sync logic deleted.
  }
  Future<void> syncGoldPrices() async {
    // Migrated fully to Firebase Firestore.
    // SQFlite sync logic deleted.
  }
}

