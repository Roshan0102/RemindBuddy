import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'storage_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> init() async {
    // Firebase handles token persistence automatically.
  }

  bool get isAuthenticated => _auth.currentUser != null;
  String? get userId => _auth.currentUser?.uid;

  Future<void> login(String emailOrUsername, String password) async {
    String email = emailOrUsername.trim();
    
    // If not an email, try lookup by username
    if (!email.contains('@')) {
      final usernameDoc = await _db.collection('usernames').doc(email.toLowerCase()).get();
      if (!usernameDoc.exists) {
        throw Exception('Username not found');
      }
      email = usernameDoc.data()?['email'];
    }

    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      print("Logged in via Firebase as ${credential.user?.uid}");

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_sync_time');

    } catch (e) {
      print("Firebase Login failed: $e");
      throw Exception('Login failed: ${e.toString()}');
    }
  }

  Future<void> signup(String username, String email, String password) async {
    try {
      // 1. Check if username is taken
      print('🔍 Checking username existence for: $username');
      final usernameDoc = await _db.collection('usernames').doc(username.toLowerCase()).get();
      if (usernameDoc.exists) {
        throw Exception('Username already taken');
      }

      // 2. Create Auth User
      print('🔐 Creating auth user for: $email');
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // Wait a moment for auth state to propagate
      await Future.delayed(const Duration(milliseconds: 500));
      
      // 3. Save username map
      print('💾 Saving username map for UID: ${credential.user?.uid}');
      await _db.collection('usernames').doc(username.toLowerCase()).set({
        'email': email,
        'uid': credential.user?.uid,
      });

      // 4. Update display name
      await credential.user?.updateDisplayName(username);
      
      print("✅ Signed up via Firebase as ${credential.user?.uid}");
    } catch (e) {
      print("❌ Firebase Signup failed: $e");
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
