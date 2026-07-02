import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_screen.dart';
import 'notification_control_screen.dart';
import '../services/update_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _username;

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

  Future<void> _loadUsername() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    if (user.displayName != null && user.displayName!.isNotEmpty) {
      setState(() {
        _username = user.displayName;
      });
    }

    try {
      final query = await FirebaseFirestore.instance
          .collection('usernames')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        final doc = query.docs.first;
        final name = doc.id; // Document ID is the lowercased username
        setState(() {
          _username = name;
        });
      }
    } catch (e) {
      print('Error loading username: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 12),
          // My Profile / Account
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: Icon(
                user != null ? Icons.account_circle : Icons.login,
                color: Colors.teal,
                size: 32,
              ),
              title: Text(
                user != null ? 'My Profile' : 'Login / Register',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                user != null ? (_username ?? user.email ?? 'Authenticated') : 'Log in to sync your data',
                style: const TextStyle(color: Colors.grey),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AuthScreen()),
                ).then((_) {
                  setState(() {});
                  _loadUsername();
                });
              },
            ),
          ),
          
          // Customize Bottom Bar Option
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const Icon(Icons.dashboard_customize, color: Colors.purple, size: 28),
              title: const Text('Customize Bottom Bar', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Select which tabs appear on your main navigation'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(context, 'customize_bottom_bar');
              },
            ),
          ),

          // Notification Control Option
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const Icon(Icons.notifications_active, color: Colors.amber, size: 28),
              title: const Text('Notification Control', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Manage notifications for enabled features'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const NotificationControlScreen()),
                );
              },
            ),
          ),

          // Check for Updates Option
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const Icon(Icons.system_update_alt, color: Colors.deepPurple, size: 28),
              title: const Text('Check for Updates', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Look for newer versions of RemindBuddy'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                UpdateService.checkForUpdates(context, showNoUpdateMsg: true);
              },
            ),
          ),
        ],
      ),
    );
  }
}
