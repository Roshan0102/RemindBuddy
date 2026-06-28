import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/log_service.dart';

class NotificationControlScreen extends StatefulWidget {
  const NotificationControlScreen({super.key});

  @override
  State<NotificationControlScreen> createState() => _NotificationControlScreenState();
}

class _NotificationControlScreenState extends State<NotificationControlScreen> {
  bool _isLoading = true;
  List<String> _enabledModules = [];
  Map<String, bool> _notifPrefs = {
    'gold': true,
    'shifts': true,
    'reminders': true,
  };

  @override
  void initState() {
    super.initState();
    _loadNotificationPreferences();
  }

  Future<void> _loadNotificationPreferences() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final enabled = List<String>.from(data['enabledModules'] ?? ['gold']);
        final prefs = Map<String, dynamic>.from(data['notificationPreferences'] ?? {});
        
        setState(() {
          _enabledModules = enabled;
          _notifPrefs = {
            'gold': prefs['gold'] ?? true,
            'shifts': prefs['shifts'] ?? true,
            'reminders': prefs['reminders'] ?? true,
          };
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      LogService().error("Error loading notification preferences", e);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveNotificationPreference(String key, bool value) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    setState(() {
      _notifPrefs[key] = value;
    });

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'notificationPreferences': {
          key: value,
        }
      }, SetOptions(merge: true));
    } catch (e) {
      LogService().error("Error saving notification preference", e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save preference: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notification Control')),
        body: const Center(child: Text('Please log in to manage notification preferences.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Control'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: ListView(
                children: [
                  const Text(
                    'Manage your push notifications for each enabled feature below.',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  
                  // Gold rates
                  if (_enabledModules.contains('gold'))
                    _buildPreferenceTile(
                      key: 'gold',
                      title: 'Gold Rates & Advice',
                      subtitle: 'Daily Gold Rate updates & Chit buy recommendations (11:00 AM & 11:01 AM)',
                      icon: Icons.monetization_on,
                      iconColor: Colors.amber,
                    ),

                  // Shifts
                  if (_enabledModules.contains('shifts'))
                    _buildPreferenceTile(
                      key: 'shifts',
                      title: 'Shift Reminders',
                      subtitle: 'Reminder about your shift for tomorrow (10:00 PM)',
                      icon: Icons.work_history,
                      iconColor: Colors.purple,
                    ),

                  // Calendar & Daily Reminders
                  if (_enabledModules.contains('reminders') || _enabledModules.contains('daily_reminders'))
                    _buildPreferenceTile(
                      key: 'reminders',
                      title: 'Calendar & Daily Reminders',
                      subtitle: 'Push notifications for custom calendar events and recurring tasks',
                      icon: Icons.alarm_on,
                      iconColor: Colors.blue,
                    ),

                  if (!_enabledModules.contains('gold') &&
                      !_enabledModules.contains('shifts') &&
                      !_enabledModules.contains('reminders') &&
                      !_enabledModules.contains('daily_reminders'))
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Text(
                          'You do not have any notification-enabled features active right now.',
                          style: TextStyle(color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildPreferenceTile({
    required String key,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SwitchListTile(
        secondary: CircleAvatar(
          backgroundColor: iconColor.withOpacity(0.1),
          child: Icon(icon, color: iconColor),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        value: _notifPrefs[key] ?? true,
        onChanged: (val) => _saveNotificationPreference(key, val),
        activeColor: Colors.teal,
      ),
    );
  }
}
