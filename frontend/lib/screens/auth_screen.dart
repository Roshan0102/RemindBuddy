import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktopWeb = constraints.maxWidth >= 768;

        if (isDesktopWeb && !_isAuthenticated) {
          return _buildWebSplitScreenAuthView(context);
        }

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: _isAuthenticated
                ? IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                : null,
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
      },
    );
  }

  Widget _buildWebSplitScreenAuthView(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // LEFT HERO PANEL
          Expanded(
            flex: 6,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0F172A),
                    Color(0xFF1E3A8A),
                    Color(0xFF0284C7),
                  ],
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // App Brand Logo & Name
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white30, width: 2),
                        ),
                        child: const Icon(Icons.alarm_add, color: Colors.white, size: 36),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'RemindBuddy',
                        style: GoogleFonts.pacifico(
                          fontSize: 38,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 36),

                  Text(
                    'Your All-in-One Intelligent\nProductivity & Finance Suite',
                    style: GoogleFonts.outfit(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Manage daily reminders, work shifts, 22K gold rates, split expenses, and AI job applications seamlessly in one dashboard.',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      color: Colors.white70,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 44),

                  // 4 Feature Cards Grid
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      _buildHeroFeatureBadge(Icons.alarm_on, Colors.amber, 'Smart Reminders', 'Calendar & Shift tracking'),
                      _buildHeroFeatureBadge(Icons.monetization_on, Colors.yellowAccent, 'Gold & Finance', 'Live rates & split expenses'),
                      _buildHeroFeatureBadge(Icons.psychology, Colors.lightBlueAccent, 'Gemini AI Assistant', 'Job applications & resume'),
                      _buildHeroFeatureBadge(Icons.shield, Colors.tealAccent, 'Secure Vault', 'PIN encrypted vault storage'),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // RIGHT LOGIN FORM PANEL
          Expanded(
            flex: 5,
            child: Container(
              color: const Color(0xFF0F172A),
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 440),
                    padding: const EdgeInsets.all(36),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white12, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.blue.withValues(alpha: 0.15),
                              border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.4), width: 2),
                            ),
                            child: const Icon(
                              Icons.lock_person_rounded,
                              size: 44,
                              color: Colors.blueAccent,
                            ),
                          ),
                          const SizedBox(height: 20),

                          Text(
                            'Welcome Back',
                            style: GoogleFonts.outfit(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Sign in to access your RemindBuddy workspace',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 28),

                          Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                _buildWebTextField(
                                  controller: _emailController,
                                  label: 'Email or Username',
                                  icon: Icons.person_outline,
                                  validator: (val) {
                                    if (val == null || val.isEmpty) return 'Please enter your login';
                                    if (val.length < 3) return 'Login too short';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),

                                _buildWebTextField(
                                  controller: _passwordController,
                                  label: 'Password',
                                  icon: Icons.lock_outline,
                                  isPassword: true,
                                  validator: (val) => val != null && val.length > 5 ? null : 'Password too short (min 6)',
                                ),

                                const SizedBox(height: 28),

                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      gradient: LinearGradient(
                                        colors: [Colors.blue.shade600, Colors.blue.shade800],
                                      ),
                                    ),
                                    child: ElevatedButton(
                                      onPressed: _isLoading ? null : _submit,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shadowColor: Colors.transparent,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: _isLoading
                                          ? const SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                            )
                                          : Text(
                                              'SIGN IN',
                                              style: GoogleFonts.outfit(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                                letterSpacing: 1.1,
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroFeatureBadge(IconData icon, Color iconColor, String title, String subtitle) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebTextField({
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
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.blueAccent, size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
        ),
        filled: true,
        fillColor: const Color(0xFF0F172A),
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
                 backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
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
                      color: Colors.white.withValues(alpha: 0.1),
                      border: Border.all(color: Colors.white24, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
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
                    'Welcome Back',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 40),

                  Card(
                    elevation: 12,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    color: Colors.white.withValues(alpha: 0.95), 
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            _buildTextField(
                              controller: _emailController,
                              label: 'Email or Username',
                              icon: Icons.person_pin,
                              validator: (val) {
                                if (val == null || val.isEmpty) return 'Please enter your login';
                                if (val.length < 3) return 'Login too short';
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            
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
                                      'LOGIN',
                                      style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold),
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
