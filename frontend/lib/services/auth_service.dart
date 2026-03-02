import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'storage_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> init() async {
    // Firebase handles token persistence automatically.
    // We just wait for the currentUser to be hydrated if needed.
  }

  bool get isAuthenticated => _auth.currentUser != null;
  String? get userId => _auth.currentUser?.uid;

  Future<void> login(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      print("Logged in via Firebase as ${credential.user?.uid}");

      // Clear sync times for future migrations
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_sync_time');

    } catch (e) {
      print("Firebase Login failed: $e");
      throw Exception('Login failed: ${e.toString()}');
    }
  }

  Future<void> signup(String username, String email, String password) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // Update display name
      await credential.user?.updateDisplayName(username);
      
      print("Signed up via Firebase as ${credential.user?.uid}");
    } catch (e) {
      print("Firebase Signup failed: $e");
      throw Exception('Signup failed: ${e.toString()}');
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
    final storage = StorageService();
    await storage.logoutAndClearData();
    print('User logged out natively via Firebase');
  }
}
