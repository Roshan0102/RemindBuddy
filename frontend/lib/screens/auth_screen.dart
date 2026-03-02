import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';

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
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
       setState(() {
         _isAuthenticated = true;
         _currentUserEmail = user.email ?? "User";
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
        await auth.login(_emailController.text.trim(), _passwordController.text.trim());
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
     await AuthService().logout();
     setState(() {
       _isAuthenticated = false;
       _isLogin = true;
       _usernameController.clear();
       _passwordController.clear();
       _emailController.clear();
     });
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
           
           // Logout
           SizedBox(
             width: double.infinity,
             height: 50,
             child: OutlinedButton.icon(
               icon: const Icon(Icons.logout, color: Colors.white),
               label: const Text("LOGOUT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
               style: OutlinedButton.styleFrom(
                 side: const BorderSide(color: Colors.redAccent),
                 backgroundColor: Colors.redAccent.withOpacity(0.2),
                 shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
               ),
               onPressed: _logout,
             ),
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
                            _buildTextField(
                              controller: _emailController,
                              label: _isLogin ? 'Email or Username' : 'Email Address',
                              icon: _isLogin ? Icons.person_pin : Icons.email_outlined,
                              validator: (val) {
                                if (val == null || val.isEmpty) return 'Please enter your login';
                                if (!_isLogin && !val.contains('@')) return 'Enter a valid email';
                                if (val.length < 3) return 'Login too short';
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            
                            if (!_isLogin) ...[
                              _buildTextField(
                                controller: _usernameController,
                                label: 'Display Name',
                                icon: Icons.person_outline,
                                validator: (val) => val != null && val.length > 2 ? null : 'Name too short',
                              ),
                              const SizedBox(height: 16),
                            ],
                            
                            _buildTextField(
                              controller: _passwordController,
                              label: 'Password',
                              icon: Icons.lock_outline,
                              isPassword: true,
                              validator: (val) => val != null && val.length > 5 ? null : 'Password too short (min 6)',
                            ),
                            
                            const SizedBox(height: 30),
                            
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
