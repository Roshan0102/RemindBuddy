import 'package:pocketbase/pocketbase.dart';
void main() async {
  final pb = PocketBase('http://35.237.49.45:8090');
  try {
    final response = await pb.send(
      '/api/admins/auth-with-password',
      method: 'POST',
      body: {'identity': 'Roshan', 'password': 'jdjrlm@2012'},
    );
    pb.authStore.save(response['token'] as String, null);
    
    final col = await pb.collections.getOne('notes');
    print(col.toJson());
  } catch (e) {
    print('Err: $e');
  }
}
