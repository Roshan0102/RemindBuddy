
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import 'main_screen.dart';
import 'admin_setup_screen.dart';
import '../services/pb_migration_service.dart';

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
       // Ideally fetch user details from storage or Auth Service
       // For now, let's assume we are logged in.
       // We can try to get email from AuthService if available
       final auth = AuthService();
       setState(() {
         _isAuthenticated = true;
         _currentUserEmail = auth.pb.authStore.model?.email ?? "User"; // Get from PB store
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
        // After successful login/signup, update state to show "Profile View"
        await _checkAuthStatus(); // Refresh state
        setState(() => _isLoading = false);
        
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
            content: Text(_isLogin ? 'Welcome back!' : 'Account Created!'),
            backgroundColor: Colors.green,
          ),
        );
        // We stay on this screen now to let them click "Migrate", 
        // OR we can navigate to MainScreen. 
        // Current User Flow: Login -> Main Screen -> Settings -> Migrate.
        // So upon first login from this screen, let's just refresh the UI to show Migration options
        // instead of forcing navigation away, so they see the "Run Migrate" button immediately.
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
    // Navigate to Admin/Migration Setup
    Navigator.of(context).push(
       MaterialPageRoute(builder: (_) => const AdminSetupScreen()),
    );
  }
  
  Future<void> _forgotPassword() async {
    if (_usernameController.text.isEmpty && _emailController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter your Email or Username to reset password')),
        );
        return;
    }
    // Simple mock or actual implementation
    // PocketBase requestPasswordReset(email)
    final email = _emailController.text.isNotEmpty ? _emailController.text : _usernameController.text; // Assuming they might type email in username
     try {
        final auth = AuthService();
        await auth.pb.collection('users').requestPasswordReset(email);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset email sent! Check your inbox.')),
        );
     } catch(e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send reset email: $e')),
        );
     }
  }

  @override
  Widget build(BuildContext context) {
    // Premium Gradient Background
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
                  // Logo / Icon
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
                  
                  // Title
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

                  // Auth Card
                  Card(
                    elevation: 12,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    color: Colors.white.withOpacity(0.95), // Slight transparency
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
                            
                            // Forgot Password Button (Only for Login)
                            if (_isLogin)
                                Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                        onPressed: _forgotPassword,
                                        child: Text("Forgot Password?", style: TextStyle(color: Colors.blue.shade900)),
                                    ),
                                ),

                            SizedBox(height: _isLogin ? 10 : 30),
                            
                            // Action Button
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
                            
                            // Switch Mode
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
