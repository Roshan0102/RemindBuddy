import 'package:pocketbase/pocketbase.dart';

void main() async {
  final pb = PocketBase('http://35.237.49.45:8090');
  try {
      await pb.collections.create(body: {
        'name': 'test_json_col',
        'type': 'base',
        'schema': [
           {'name': 'json_data', 'type': 'json'},
        ],
      });
      print("Created successfully");
      await pb.collections.delete('test_json_col');
  } catch (e) {
      print("Error creating: $e");
  }
}
