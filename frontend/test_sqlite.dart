import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

void main() async {
  sqfliteFfiInit();
  var databaseFactory = databaseFactoryFfi;
  final dbPath = p.join(await databaseFactory.getDatabasesPath(), 'test_sync.db');
  
  final db = await databaseFactory.openDatabase(dbPath, options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, version) async {
        await db.execute('CREATE TABLE shifts(id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT UNIQUE, isSynced INTEGER DEFAULT 0)');
      }
  ));
  
  await db.insert('shifts', {'date': '2026-02-01'});
  final list1 = await db.query('shifts');
  print('List 1: $list1');
  
  await db.insert('shifts', {'date': '2026-02-01'}, conflictAlgorithm: ConflictAlgorithm.replace);
  final list2 = await db.query('shifts');
  print('List 2: $list2');
  
  final query0 = await db.query('shifts', where: 'isSynced = 0');
  print('Query 0: $query0');
  
  await db.close();
}
