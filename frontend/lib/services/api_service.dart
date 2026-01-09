import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/task.dart';

class ApiService {
  // GCP Servers
  static const String baseUrl = 'http://35.237.49.45/api/tasks';

  Future<List<Task>> getTasks() async {
    try {
      final response = await http.get(Uri.parse(baseUrl));
      if (response.statusCode == 200) {
        List<dynamic> body = jsonDecode(response.body);
        return body.map((dynamic item) => Task.fromJson(item)).toList();
      } else {
        throw Exception('Failed to load tasks');
      }
    } catch (e) {
      print('Error fetching tasks: $e');
      return []; // Return empty list on error (offline mode handling)
    }
  }

  Future<Task?> createTask(Task task) async {
    try {
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(task.toJson()),
      );
      if (response.statusCode == 201) {
        return Task.fromJson(jsonDecode(response.body));
      }
    } catch (e) {
      print('Error creating task: $e');
    }
    return null;
  }
}
