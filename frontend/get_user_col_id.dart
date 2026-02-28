import 'package:pocketbase/pocketbase.dart';
import 'dart:math';

void main() async {
  final pb = PocketBase('http://35.237.49.45:8090');
  
  final randString = Random().nextInt(1000000).toString();
  try {
      final body = <String, dynamic>{
        "username": 'TestUser$randString',
        "email": 'testuser$randString@example.com',
        "emailVisibility": true,
        "password": 'password123',
        "passwordConfirm": 'password123',
        "name": 'TestUser',
      };

      final record = await pb.collection('users').create(body: body);
      print("USER COLLECTION ID IS: ${record.collectionId}");
      pb.authStore.save('token', record);
      
      // Cleanup
      await pb.collection('users').authWithPassword('testuser$randString@example.com', 'password123');
      await pb.collection('users').delete(record.id);
  } catch (e) {
      print("Error: $e");
  }
}
