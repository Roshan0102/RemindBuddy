
import 'package:pocketbase/pocketbase.dart';

import 'storage_service.dart';
import 'sync_service.dart';
import 'dart:convert';
import 'pb_debug_logger.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  // Replace with your actual server IP and port
  // IMPORTANT: Use the public IP that the phone can access, NOT 127.0.0.1 or localhost
  static const String _baseUrl = 'http://35.237.49.45:8090';
  
  final PocketBase pb = PocketBase(_baseUrl);

  Future<void> init() async {
    // Check if we have a saved token
    final storage = StorageService();
    final token = await storage.getAuthToken();
    
    if (token != null && token.isNotEmpty) {
      pb.authStore.save(token, null); 
      // Fetch user data with auth refresh so that SyncService knows who is logged in
      try {
        final authData = await pb.collection('users').authRefresh();
        pb.authStore.save(authData.token, authData.record);
      } catch (e) {
        pbLog("Auth refresh failed: $e. Your session may have expired.");
        if (e is ClientException && (e.statusCode == 401 || e.statusCode == 404)) {
            pbLog("⚠️ Invalid session detected. Logging out...");
            await logout();
            return;
        }
      }
      
      // Trigger sync
      try {
        SyncService(pb).syncAll();
      } catch (e) { print(e); }
    }
  }

  bool get isAuthenticated => pb.authStore.isValid;
  String? get userId {
    if (pb.authStore.model != null) return pb.authStore.model.id;
    final token = pb.authStore.token;
    if (token.isEmpty) return null;
    try {
      final parts = token.split('.');
      if (parts.length == 3) {
        final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
        return payload['id'];
      }
    } catch (_) {}
    return null;
  }

  Future<void> login(String email, String password) async {
    try {
      final authData = await pb.collection('users').authWithPassword(email, password);
      
      // Save token locally
      final storage = StorageService();
      await storage.saveAuthToken(pb.authStore.token, authData.record?.data.toString() ?? "");
      

      print("Logged in as ${authData.record?.id}");
      
      // Trigger Sync
      try {
        SyncService(pb).syncAll();
      } catch (e) { print("Login sync failed: $e"); }
    } catch (e) {
      print("Login failed: $e");
      throw Exception('Login failed: $e');
    }
  }

  Future<void> signup(String username, String email, String password) async {
    try {
      final body = <String, dynamic>{
        "username": username,
        "email": email,
        "emailVisibility": true,
        "password": password,
        "passwordConfirm": password,
        "name": username,
      };

      await pb.collection('users').create(body: body);
      
      // Auto login after signup
      await login(email, password);
      
    } catch (e) {
      print("Signup failed: $e");
      throw Exception('Signup failed: $e');
    }
  }

  Future<void> logout() async {
    pb.authStore.clear();
    final storage = StorageService();
    await storage.logoutAndClearData();
  }
}
