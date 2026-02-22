import 'package:pocketbase/pocketbase.dart';
void main() async {
  final pb = PocketBase('http://35.237.49.45:8090');
  try {
    // Authenticate as roshan
    await pb.collection('users').authWithPassword('roshanjustinjr2002@gmail.com', 'jdjrlm@2012');
    print("Logged in as user. ID: ${pb.authStore.model.id}");
    
    // Create note
    final record = await pb.collection('notes').create(body: {
      'title': 'Test note',
      'content': 'Test content',
      'date': '2026-02-22',
      'is_locked': false,
      'user': pb.authStore.model.id,
    });
    print('Note created: ${record.id}');
  } on ClientException catch (e) {
    print('ClientException: ${e.statusCode} ${e.response}');
  } catch (e) {
    print('Error: $e');
  }
}
