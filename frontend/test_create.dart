import 'package:pocketbase/pocketbase.dart';

void main() async {
  final pb = PocketBase('http://35.237.49.45:8090');
  try {
    // 1. Force use admin credentials user types
    final response = await pb.send(
      '/api/admins/auth-with-password',
      method: 'POST',
      body: {'identity': 'admin@remindbuddy.com', 'password': 'jdjrlm@2012'}, // Using likely email and password
    );
    pb.authStore.save(response['token'] as String, null);
    
    // 2. run create shifts_data
    await pb.collections.create(body: {
        'name': 'shifts_data_test',
        'type': 'base',
        'schema': [
          {'name': 'month_year', 'type': 'text'},
          {'name': 'json_data', 'type': 'json'},
          {
            'name': 'user', 
            'type': 'relation', 
            'options': {
              'collectionId': '_pb_users_auth_',
              'cascadeDelete': true,
              'maxSelect': 1,
            }
          },
        ],
      });
      print("SUCCESS CREATING SHIFTS_DATA_TEST");
  } catch(e) {
    print("MIGRATION ERROR: $e");
  }
}
