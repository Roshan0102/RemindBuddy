import 'package:pocketbase/pocketbase.dart';

class PbMigrationService {
  final PocketBase pb;

  PbMigrationService(this.pb);

  Future<void> createCollections(String adminEmail, String adminPassword) async {
    // Attempt authentication
    try {
      // 1. Try legacy Admin auth (for PocketBase v0.22 and below) 
      // The Dart SDK 0.23+ redirects pb.admins to _superusers, which fails on v0.22
      final response = await pb.send(
        '/api/admins/auth-with-password',
        method: 'POST',
        body: {'identity': adminEmail, 'password': adminPassword},
      );
      
      final token = response['token'] as String;
      pb.authStore.save(token, null);
      print("Authenticated natively to legacy admin path (/api/admins).");
      
    } catch (e) {
      print("Legacy Admin auth failed: $e. Trying via newer _superusers/users collections...");
      try {
        await pb.collection('users').authWithPassword(adminEmail, adminPassword);
        print("Authenticated as regular user (admin access presumed).");
      } catch (e2) {
         throw Exception("Authentication failed. \nAdmin Error: $e\nUser Error: $e2");
      }
    }
    
    // Get users collection ID dynamically
    String usersCollectionId = '_pb_users_auth_';
    try {
      final usersCol = await pb.collections.getOne('users');
      usersCollectionId = usersCol.id;
      print("Found users collection with id: $usersCollectionId");
    } catch (e) {
      print("Warning: could not fetch users collection id, using default.");
    }

    // Create 'tasks' collection
    await _createCollection(
      name: 'tasks',
      schema: [
        {'name': 'title', 'type': 'text', 'required': false},
        {'name': 'description', 'type': 'text', 'required': false},
        {'name': 'date', 'type': 'text', 'required': false},
        {'name': 'time', 'type': 'text', 'required': false},
        {'name': 'repeat', 'type': 'text', 'required': false},
        {'name': 'is_annoying', 'type': 'bool', 'required': false},
        {'name': 'is_completed', 'type': 'bool', 'required': false},
        {
          'name': 'user', 
          'type': 'relation', 
          'required': true,
          'options': {
            'collectionId': usersCollectionId,
            'cascadeDelete': true,
            'maxSelect': 1,
          }
        },
      ],
    );

    // Create 'notes' collection
    await _createCollection(
      name: 'notes',
      schema: [
        {'name': 'title', 'type': 'text'},
        {'name': 'content', 'type': 'text'},
        {'name': 'date', 'type': 'text'},
        {'name': 'is_locked', 'type': 'bool'},
        {
          'name': 'user', 
          'type': 'relation', 
          'options': {
            'collectionId': usersCollectionId,
            'cascadeDelete': true,
            'maxSelect': 1,
          }
        },
      ],
    );

    // Create 'daily_reminders' collection
    await _createCollection(
      name: 'daily_reminders',
      schema: [
        {'name': 'title', 'type': 'text'},
        {'name': 'description', 'type': 'text'},
        {'name': 'time', 'type': 'text'},
        {'name': 'is_active', 'type': 'bool'},
        {'name': 'is_annoying', 'type': 'bool'},
        {
          'name': 'user', 
          'type': 'relation', 
          'options': {
            'collectionId': usersCollectionId,
            'cascadeDelete': true,
            'maxSelect': 1,
          }
        },
      ],
    );

    // Create 'checklists' collection
    await _createCollection(
      name: 'checklists',
      schema: [
        {'name': 'title', 'type': 'text'},
        {'name': 'icon_code', 'type': 'number'},
        {'name': 'color', 'type': 'number'},
        {
          'name': 'user', 
          'type': 'relation', 
          'options': {
            'collectionId': usersCollectionId,
            'cascadeDelete': true,
            'maxSelect': 1,
          }
        },
      ],
    );

    // Create 'checklist_items' collection
    await _createCollection(
      name: 'checklist_items',
      schema: [
        {'name': 'text', 'type': 'text'},
        {'name': 'is_checked', 'type': 'bool'},
        {
          'name': 'checklist', 
          'type': 'relation', 
          'options': {
            'collectionId': 'checklists_placeholder', 
            'cascadeDelete': true,
            'maxSelect': 1,
          }
        },
        {
          'name': 'user', 
          'type': 'relation', 
          'required': true,
          'options': {
            'collectionId': usersCollectionId,
            'cascadeDelete': true,
            'maxSelect': 1,
          }
        },
      ],
    );

    // Create 'shifts' collection
    await _createCollection(
      name: 'shifts',
      schema: [
        {'name': 'date', 'type': 'text'},
        {'name': 'shift_type', 'type': 'text'},
        {'name': 'start_time', 'type': 'text'},
        {'name': 'end_time', 'type': 'text'},
        {'name': 'is_week_off', 'type': 'bool'},
        {'name': 'roster_month', 'type': 'text'},
        {
          'name': 'user', 
          'type': 'relation', 
          'options': {
            'collectionId': usersCollectionId,
            'cascadeDelete': true,
            'maxSelect': 1,
          }
        },
      ],
    );

    // Create 'shift_metadata' collection
    await _createCollection(
      name: 'shift_metadata',
      schema: [
        {'name': 'employee_name', 'type': 'text'},
        {'name': 'month', 'type': 'text'},
        {'name': 'roster_month', 'type': 'text'},
        {
          'name': 'user', 
          'type': 'relation', 
          'options': {
            'collectionId': usersCollectionId,
            'cascadeDelete': true,
            'maxSelect': 1,
          }
        },
      ],
    );

    // Create 'monthly_rosters' collection
    await _createCollection(
      name: 'monthly_rosters',
      schema: [
        {'name': 'month', 'type': 'text'},
        {'name': 'roster_month', 'type': 'text'},
        {'name': 'json_data', 'type': 'json'},
        {
          'name': 'user', 
          'type': 'relation', 
          'options': {
            'collectionId': usersCollectionId,
            'cascadeDelete': true,
            'maxSelect': 1,
          }
        },
      ],
    );
  }

  Future<void> _createCollection({required String name, required List<Map<String, dynamic>> schema}) async {
    try {
      // Check if collection exists
      try {
        await pb.collections.getOne(name); 
        // If successful, it exists.
        print('Collection $name already exists.');
        return;
      } catch (e) {
        // Not found or error, verify if 404
        // Proceed to create
      }
      
      // Resolve relation references
      for (var field in schema) {
        if (field['type'] == 'relation') {
          var options = field['options'] as Map<String, dynamic>;
          if (options['collectionId'] == 'checklists_placeholder') {
             try {
                // We need the ID of the checklists collection we just created
                final col = await pb.collections.getOne('checklists');
                options['collectionId'] = col.id;
             } catch (e) {
                print('Error finding checklists relation ID: $e');
             }
          }
        }
      }

      await pb.collections.create(body: {
        'name': name,
        'type': 'base',
        'schema': schema,
        'listRule': 'user = @request.auth.id',
        'viewRule': 'user = @request.auth.id',
        'createRule': 'user = @request.auth.id',
        'updateRule': 'user = @request.auth.id',
        'deleteRule': 'user = @request.auth.id',
      });
      print('Created collection $name');
    } catch (e) {
      print('Failed to create collection $name: $e');
      // Rethrow if critical failure? No, allow partial
    }
  }
}
