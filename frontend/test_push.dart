import 'package:pocketbase/pocketbase.dart';
import 'dart:math';

void main() async {
  final pb = PocketBase('http://35.237.49.45:8090');
  
  final randString = Random().nextInt(1000000).toString();
  try {
      final body = <String, dynamic>{
        "username": 'TestUserX$randString',
        "email": 'testuserx$randString@example.com',
        "emailVisibility": true,
        "password": 'password123',
        "passwordConfirm": 'password123',
        "name": 'TestUser',
      };

      final user = await pb.collection('users').create(body: body);
      await pb.collection('users').authWithPassword('testuserx$randString@example.com', 'password123');
      
      try {
          final noteBody = {
            'title': 'Test Note',
            'content': 'Hello World',
            'date': '2023-01-01',
            'is_locked': false,
            'user': user.id,
          };
          print("Pushing note...");
          final note = await pb.collection('notes').create(body: noteBody);
          print("Note pushed: ${note.id}");
      } catch (e) {
          print("Note error: $e");
      }
      
      // Cleanup
      await pb.collection('users').delete(user.id);
  } catch (e) {
      print("Error: $e");
  }
}
