
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import 'package:pocketbase/pocketbase.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  bool _isAuthorized = false;
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  
  List<RecordModel> _users = [];
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _checkCredentials() {
    // Hardcoded credentials as requested by user
    if (_usernameController.text == 'Roshan' && _passwordController.text == 'jdjrlm@2012') {
      setState(() {
        _isAuthorized = true;
      });
      _fetchAllUsers();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid Admin Credentials')),
      );
    }
  }

  Future<void> _fetchAllUsers() async {
    setState(() => _isLoading = true);
    try {
      final pb = AuthService().pb;
      
      // Try to authenticate as admin with the provided credentials first
      // This ensures we have permission to list users
      try {
         // Try admin auth (email/pass) - but here we have username 'Roshan'. 
         // PocketBase admins usually need email. 
         // If 'Roshan' is a username in 'users' collection with admin rights:
         await pb.collection('users').authWithPassword(_usernameController.text, _passwordController.text);
      } catch (e) {
         print("Could not auth as specific admin user, trying existing auth or public access: $e");
      }

      final records = await pb.collection('users').getFullList();
      setState(() {
        _users = records;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to fetch users: $e')),
        );
      }
    }
  }

  Future<void> _updateUserPassword(String customId) async {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset User Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: 'New Password'),
              obscureText: true,
            ),
            TextField(
              controller: confirmController,
              decoration: const InputDecoration(labelText: 'Confirm Password'),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (passwordController.text != confirmController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Passwords do not match')),
                );
                return;
              }
              if (passwordController.text.length < 5) {
                 ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password too short')),
                );
                return;
              }
              
              try {
                final pb = AuthService().pb;
                await pb.collection('users').update(customId, body: {
                  'password': passwordController.text,
                  'passwordConfirm': confirmController.text,
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password updated successfully')),
                );
              } catch (e) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to update: $e')),
                );
              }
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthorized) {
      return _buildLoginView();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Console'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchAllUsers,
          ),
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            onPressed: () => setState(() => _isAuthorized = false),
          ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView.builder(
            itemCount: _users.length,
            itemBuilder: (context, index) {
              final user = _users[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(user.getStringValue('username').substring(0, 1).toUpperCase()),
                  ),
                  title: Text(user.getStringValue('username')),
                  subtitle: Text(user.getStringValue('email').isEmpty ? 'No Email' : user.getStringValue('email')),
                  trailing: IconButton(
                    icon: const Icon(Icons.lock_reset, color: Colors.orangeAccent),
                    onPressed: () => _updateUserPassword(user.id),
                    tooltip: 'Reset Password',
                  ),
                ),
              );
            },
          ),
    );
  }

  Widget _buildLoginView() {
    return Scaffold(
      appBar: AppBar(title: const Text("Admin Access")),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.security, size: 80, color: Colors.redAccent),
              const SizedBox(height: 20),
              const Text(
                'Restricted Area',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Admin Username',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Admin Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _checkCredentials,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Access Console'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
