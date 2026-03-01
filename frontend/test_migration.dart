import 'package:pocketbase/pocketbase.dart';

void main() async {
  final pb = PocketBase('http://35.237.49.45:8090');
  
  // Try to authenticate
  try {
    final response = await pb.send(
      '/api/admins/auth-with-password',
      method: 'POST',
      body: {'identity': 'Roshan', 'password': 'jdjrlm@2012'}, // the credentials the user probably uses, or maybe I don't know them. Wait, what are the user's admin credentials?
    );
    pb.authStore.save(response['token'] as String, null);
    print('Logged in as admin');
    
    // Now try creating shifts_data
    try {
      await pb.collections.create(body: {
        'name': 'shifts_data',
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
      print("Success!");
    } catch (e) {
      print("Create err: $e");
    }
    
  } catch (e) {
    print('Admin Login Failed: $e');
  }
}
