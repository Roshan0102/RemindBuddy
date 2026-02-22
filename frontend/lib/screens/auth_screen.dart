import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';
import 'admin_setup_screen.dart';
import 'main_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  bool _isLogin = true;
  bool _isLoading = false;
  bool _isAuthenticated = false;
  String _currentUserEmail = '';
  
  final _formKey = GlobalKey<FormState>();
  
  // Controllers
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailController = TextEditingController(); 

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _animController.forward();
    
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    final isLoggedIn = await StorageService().isLoggedIn();
    if (isLoggedIn) {
       final auth = AuthService();
       // Safely access email from RecordModel
       String? email;
       try {
         final model = auth.pb.authStore.model;
         // Check if it's a RecordModel (user) or AdminModel (admin)
         // Assuming standard user for now. RecordModel accesses data via data[] map or helpers if generated.
         // But the dynamic nature means we might need to check.
         // 'email' is usually a top-level getter on AdminModel, but on RecordModel it's in the data.
         // However, pocketbase_dart RecordModel usually mimics the json structure.
         // Let's use toString() or check properties safely.
         // Actually, authStore.model is of type generic.
         // Let's try to cast or access dynamic.
         
         if (model != null) {
            // Use dynamic access to avoid strict type error if the getter is missing on specific type
            email = (model as dynamic).email; 
            // Fallback if dynamic access failed or returned null (though it throws NoSuchMethodError usually if missing)
         }
       } catch (e) {
          // If direct access fails, try accessing via data map if it's a RecordModel
          // Note: accessing .data on dynamic might also fail if it's AdminModel
          try {
             final model = auth.pb.authStore.model;
             if (model is dynamic && model.data is Map) {
                email = model.data['email'];
             }
          } catch(e2) {
             print("Error accessing email: $e2");
          }
       }
       
       setState(() {
         _isAuthenticated = true;
         _currentUserEmail = email ?? "User";
       });
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _toggleAuthMode() {
    setState(() {
      _isLogin = !_isLogin;
    });
    _animController.reset();
    _animController.forward();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    
    try {
      final auth = AuthService();
      if (_isLogin) {
        await auth.login(_usernameController.text.trim(), _passwordController.text.trim());
      } else {
        await auth.signup(
          _usernameController.text.trim(), 
          _emailController.text.trim(), 
          _passwordController.text.trim()
        );
      }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(
              content: Text(_isLogin ? 'Welcome back! Syncing...' : 'Account Created! Syncing...'),
              backgroundColor: Colors.green,
            ),
          );
        }

        // Run sync immediately after login to pull data
        try {
           final syncService = SyncService(auth.pb);
           await syncService.syncAll();
        } catch (e) {
           print("Sync error during login: $e");
        }
        
        await _checkAuthStatus(); 
        
        if (mounted) {
          setState(() => _isLoading = false);
          
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const MainScreen()),
            (route) => false,
          );
        }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString().replaceAll("Exception:", "")}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _logout() async {
     final auth = AuthService();
     auth.logout();
     await StorageService().logoutAndClearData();
     setState(() {
       _isAuthenticated = false;
       _isLogin = true;
       _usernameController.clear();
       _passwordController.clear();
       _emailController.clear();
     });
  }

  Future<void> _runMigration() async {
    Navigator.of(context).push(
       MaterialPageRoute(builder: (_) => const AdminSetupScreen()),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.blue.shade900,
              const Color(0xFF1E1E2C),
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: _isAuthenticated ? _buildProfileView() : _buildAuthView(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileView() {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
           const Icon(Icons.verified_user, size: 80, color: Colors.greenAccent),
           const SizedBox(height: 20),
           Text(
             'Signed In',
             style: GoogleFonts.poppins(
                fontSize: 28, 
                fontWeight: FontWeight.bold, 
                color: Colors.white
             ),
           ),
           Text(
             _currentUserEmail,
             style: GoogleFonts.inter(
                fontSize: 16, 
                color: Colors.white70
             ),
           ),
           const SizedBox(height: 40),
           
           // Migration Button
           SizedBox(
             width: double.infinity,
             height: 60,
             child: ElevatedButton.icon(
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text("Run Migration / Sync Setup"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigoAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              onPressed: _runMigration,
             ),
           ),
           const SizedBox(height: 15),
           const Text(
             "Click above to initialize your cloud database and sync local data.",
             textAlign: TextAlign.center,
             style: TextStyle(color: Colors.white54, fontSize: 12),
           ),
           
           const SizedBox(height: 40),
           
           // Logout
           TextButton.icon(
             icon: const Icon(Icons.logout, color: Colors.redAccent),
             label: const Text("Logout", style: TextStyle(color: Colors.redAccent)),
             onPressed: _logout,
           )
        ],
      );
  }

  Widget _buildAuthView() {
     return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.1),
                      border: Border.all(color: Colors.white24, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 20,
                          spreadRadius: 5,
                        )
                      ],
                    ),
                    child: const Icon(
                      Icons.lock_person_rounded,
                      size: 60,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 30),
                  
                  Text(
                    'RemindBuddy',
                    style: GoogleFonts.poppins(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    _isLogin ? 'Welcome Back' : 'Join Us Today',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 40),

                  Card(
                    elevation: 12,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    color: Colors.white.withOpacity(0.95), 
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            if (!_isLogin) ...[
                               _buildTextField(
                                controller: _emailController,
                                label: 'Email Address',
                                icon: Icons.email_outlined,
                                validator: (val) => val != null && val.contains('@') ? null : 'Enter a valid email',
                              ),
                              const SizedBox(height: 16),
                            ],
                            
                            _buildTextField(
                              controller: _usernameController,
                              label: 'Username',
                              icon: Icons.person_outline,
                              validator: (val) => val != null && val.length > 3 ? null : 'Username too short',
                            ),
                            const SizedBox(height: 16),
                            
                            _buildTextField(
                              controller: _passwordController,
                              label: 'Password',
                              icon: Icons.lock_outline,
                              isPassword: true,
                              validator: (val) => val != null && val.length > 5 ? null : 'Password too short',
                            ),
                            
                            SizedBox(height: 30),
                            
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _submit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue.shade800,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 5,
                                ),
                                child: _isLoading 
                                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : Text(
                                      _isLogin ? 'LOGIN' : 'SIGN UP',
                                      style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                              ),
                            ),
                            
                            const SizedBox(height: 20),
                            
                            TextButton(
                              onPressed: _toggleAuthMode,
                              child: RichText(
                                text: TextSpan(
                                  style: const TextStyle(color: Colors.black54),
                                  children: [
                                    TextSpan(text: _isLogin ? "Don't have an account? " : "Already have an account? "),
                                    TextSpan(
                                      text: _isLogin ? "Sign Up" : "Login",
                                      style: TextStyle(
                                        color: Colors.blue.shade800,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.blue.shade800),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.blue, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
    );
  }
}
