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
    'gold_rates': true,
    'gold_advice': true,
    'shifts': true,
    'calendar_reminders': true,
    'daily_reminders': true,
    'walkin': true,
    'events': true,
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
            'gold_rates': prefs['gold_rates'] ?? prefs['gold'] ?? true,
            'gold_advice': prefs['gold_advice'] ?? prefs['gold'] ?? true,
            'shifts': prefs['shifts'] ?? true,
            'calendar_reminders': prefs['calendar_reminders'] ?? prefs['reminders'] ?? true,
            'daily_reminders': prefs['daily_reminders'] ?? prefs['reminders'] ?? true,
            'walkin': prefs['walkin'] ?? true,
            'events': prefs['events'] ?? true,
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
                  
                  // Gold Rates
                  if (_enabledModules.contains('gold')) ...[
                    _buildPreferenceTile(
                      key: 'gold_rates',
                      title: 'Gold Rate Updates',
                      subtitle: 'Daily Gold Rate updates (11:00 AM)',
                      icon: Icons.trending_up,
                      iconColor: Colors.amber,
                    ),
                    _buildPreferenceTile(
                      key: 'gold_advice',
                      title: 'Gold Chit Recommendations',
                      subtitle: 'Daily recommendations & chit advice (11:01 AM)',
                      icon: Icons.assistant,
                      iconColor: Colors.amber,
                    ),
                  ],

                  // Shifts
                  if (_enabledModules.contains('shifts'))
                    _buildPreferenceTile(
                      key: 'shifts',
                      title: 'Shift Reminders',
                      subtitle: 'Reminder about your shift for tomorrow (10:00 PM)',
                      icon: Icons.work_history,
                      iconColor: Colors.purple,
                    ),

                  // Calendar Events
                  if (_enabledModules.contains('reminders'))
                    _buildPreferenceTile(
                      key: 'calendar_reminders',
                      title: 'Calendar Event Alerts',
                      subtitle: 'Push notifications for custom calendar events',
                      icon: Icons.calendar_today,
                      iconColor: Colors.indigo,
                    ),

                  // Daily Reminders
                  if (_enabledModules.contains('daily_reminders'))
                    _buildPreferenceTile(
                      key: 'daily_reminders',
                      title: 'Daily Reminders Alerts',
                      subtitle: 'Push notifications for recurring tasks',
                      icon: Icons.alarm_on,
                      iconColor: Colors.blue,
                    ),

                  // Walk-In Drives
                  if (_enabledModules.contains('walkin'))
                    _buildPreferenceTile(
                      key: 'walkin',
                      title: 'Walk-In Drive Alerts',
                      subtitle: 'Alerts when new DevOps/Cloud/SRE Walk-In drives are found (8:00 PM)',
                      icon: Icons.directions_walk,
                      iconColor: Colors.lightBlue,
                    ),

                  // Tech Events
                  if (_enabledModules.contains('events'))
                    _buildPreferenceTile(
                      key: 'events',
                      title: 'Tech Event Alerts',
                      subtitle: 'Alerts when new Tech events or meetups are found (7:00 PM)',
                      icon: Icons.event,
                      iconColor: Colors.green,
                    ),

                  if (!_enabledModules.contains('gold') &&
                      !_enabledModules.contains('shifts') &&
                      !_enabledModules.contains('reminders') &&
                      !_enabledModules.contains('daily_reminders') &&
                      !_enabledModules.contains('walkin') &&
                      !_enabledModules.contains('events'))
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
        activeColor: iconColor,
      ),
    );
  }
}
