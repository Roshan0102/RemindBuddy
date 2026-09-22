import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/log_service.dart';
import '../services/notification_service.dart';

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
    'finance_bills': true,
    'finance_nightly_tagging': true,
    'calendar_reminders': true,
    'daily_reminders': true,
    'walkin': true,
    'walkin_email': true,
    'events': true,
    'events_email': true,
    'job_assistant': true,
    'job_assistant_email': true,
    'astro_calendar': false,
    'desktop_notifications': true,
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
            'finance_bills': prefs['finance_bills'] ?? prefs['finance'] ?? true,
            'finance_nightly_tagging': prefs['finance_nightly_tagging'] ?? prefs['finance'] ?? true,
            'calendar_reminders': prefs['calendar_reminders'] ?? prefs['reminders'] ?? true,
            'daily_reminders': prefs['daily_reminders'] ?? prefs['reminders'] ?? true,
            'walkin': prefs['walkin'] ?? prefs['walkins'] ?? true,
            'walkin_email': prefs['walkin_email'] ?? prefs['walkins_email'] ?? true,
            'events': prefs['events'] ?? true,
            'events_email': prefs['events_email'] ?? true,
            'job_assistant': prefs['job_assistant'] ?? true,
            'job_assistant_email': prefs['job_assistant_email'] ?? true,
            'astro_calendar': prefs['astro_calendar'] ?? false,
            'desktop_notifications': prefs['desktop_notifications'] ?? true,
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

  Future<void> _showVapidKeySetupDialog() async {
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.vpn_key_rounded, color: Color(0xFF6366F1)),
            SizedBox(width: 8),
            Text('Web Push VAPID Key', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your Firebase Web Push public certificate (VAPID key) to activate push notifications on Web, iPhone PWA & Android:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'Paste Public VAPID Key (starts with B...)',
                hintStyle: const TextStyle(fontSize: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            const Text(
              'Found in Firebase Console > Project Settings > Cloud Messaging > Web Push certificates.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final key = controller.text.trim();
              if (key.isEmpty) return;
              Navigator.pop(ctx);
              final res = await NotificationService().requestWebPushPermission(customVapidKey: key);
              if (!mounted) return;
              if (res['success'] == true) {
                await _saveNotificationPreference('desktop_notifications', true);
                if (!mounted) return;
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('🚀 Web Push notifications successfully activated!'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(res['message'] ?? 'Failed to activate Web Push.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Save & Enable'),
          ),
        ],
      ),
    );
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
                    'Manage your push notifications and email alerts for each enabled feature below.',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),

                  // Web Push Notifications (Mobile PWA & Desktop) Master Switch
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.indigo.withValues(alpha: 0.4)
                            : Colors.indigo.shade200,
                        width: 1.5,
                      ),
                    ),
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFEEF2FF),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
                          child: SwitchListTile(
                            secondary: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.notifications_active_rounded, color: Color(0xFF6366F1), size: 22),
                            ),
                            title: const Text(
                              'Web Push Notifications',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            subtitle: const Text(
                              'Receive push alerts on your phone (iPhone PWA & Android) or PC even when RemindBuddy is closed',
                              style: TextStyle(fontSize: 12),
                            ),
                            value: _notifPrefs['desktop_notifications'] ?? true,
                            activeThumbColor: const Color(0xFF6366F1),
                            onChanged: (val) async {
                              final messenger = ScaffoldMessenger.of(context);
                              if (val && kIsWeb) {
                                final res = await NotificationService().requestWebPushPermission();
                                if (!mounted) return;
                                if (res['needsVapidKey'] == true) {
                                  await _showVapidKeySetupDialog();
                                  return;
                                } else if (res['denied'] == true) {
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text('Notifications are blocked by your browser settings. Please allow notifications in your browser address bar or site settings.'),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                  return;
                                } else if (res['success'] == true) {
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text('🚀 Web Push notifications active on this device!'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              } else if (!val && kIsWeb) {
                                await NotificationService().disableWebPush();
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Web Push notifications disabled for this device.'),
                                  ),
                                );
                              }
                              await _saveNotificationPreference('desktop_notifications', val);
                            },
                          ),
                        ),
                        if (kIsWeb) ...[
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.phone_iphone_rounded, size: 15, color: Colors.indigo.shade400),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Mobile Web Push Setup Tips:',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo.shade400),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  '• iPhone: Apple requires adding RemindBuddy to your Home Screen (Safari Share ➔ Add to Home Screen) to receive push alerts.\n• Android: Native push works in Chrome, Edge, and Samsung Internet.',
                                  style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.35),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
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

                  // Finance & Bills
                  if (_enabledModules.contains('finance')) ...[
                    _buildPreferenceTile(
                      key: 'finance_bills',
                      title: 'Finance Bill Due Alerts',
                      subtitle: 'Alerts for upcoming & overdue recurring bills (9:00 AM)',
                      icon: Icons.receipt_long,
                      iconColor: Colors.teal,
                    ),
                    _buildPreferenceTile(
                      key: 'finance_nightly_tagging',
                      title: 'Daily Bank Expense Tagging',
                      subtitle: 'Reminder to tag daily bank transactions & log manual spends (9:30 PM)',
                      icon: Icons.category,
                      iconColor: Colors.cyan,
                    ),
                  ],

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
                  if (_enabledModules.contains('walkin') || _enabledModules.contains('walkins')) ...[
                    _buildPreferenceTile(
                      key: 'walkin',
                      title: 'Walk-In Drive Push Alerts',
                      subtitle: 'Push notification when new Walk-In drives are found (8:00 PM)',
                      icon: Icons.directions_walk,
                      iconColor: Colors.lightBlue,
                    ),
                    _buildPreferenceTile(
                      key: 'walkin_email',
                      title: 'Walk-In Drive Email Summary',
                      subtitle: 'Daily email summary with top walk-in venue links to your inbox',
                      icon: Icons.mark_email_read_rounded,
                      iconColor: Colors.lightBlueAccent,
                    ),
                  ],

                  // Tech Events
                  if (_enabledModules.contains('events')) ...[
                    _buildPreferenceTile(
                      key: 'events',
                      title: 'Tech Event Push Alerts',
                      subtitle: 'Push notification when new Tech events or meetups are found (7:00 PM)',
                      icon: Icons.event,
                      iconColor: Colors.green,
                    ),
                    _buildPreferenceTile(
                      key: 'events_email',
                      title: 'Tech Event Email Summary',
                      subtitle: 'Daily email summary with meetup registration links to your inbox',
                      icon: Icons.email_rounded,
                      iconColor: Colors.teal,
                    ),
                  ],

                  // AI Job Assistant
                  if (_enabledModules.contains('job_assistant')) ...[
                    _buildPreferenceTile(
                      key: 'job_assistant',
                      title: 'Job Assistant Push Alerts',
                      subtitle: 'Push notification when new job openings are auto-applied',
                      icon: Icons.rocket_launch_rounded,
                      iconColor: Colors.deepPurpleAccent,
                    ),
                    _buildPreferenceTile(
                      key: 'job_assistant_email',
                      title: 'Job Assistant Auto-Apply Email',
                      subtitle: 'Automated email summary sent to your Gmail after applying',
                      icon: Icons.mail_outline_rounded,
                      iconColor: Colors.indigoAccent,
                    ),
                  ],

                  // Astro Calendar (New Moon & Full Moon)
                  if (_enabledModules.contains('astro_calendar'))
                    _buildPreferenceTile(
                      key: 'astro_calendar',
                      title: 'Astro Calendar Alerts',
                      subtitle: 'Alerts for New Moon (Amavasai) and Full Moon (Pournami) (7:00 AM)',
                      icon: Icons.nightlight_round,
                      iconColor: Colors.deepOrange,
                    ),

                  if (!_enabledModules.contains('gold') &&
                      !_enabledModules.contains('shifts') &&
                      !_enabledModules.contains('finance') &&
                      !_enabledModules.contains('reminders') &&
                      !_enabledModules.contains('daily_reminders') &&
                      !_enabledModules.contains('walkin') &&
                      !_enabledModules.contains('walkins') &&
                      !_enabledModules.contains('events') &&
                      !_enabledModules.contains('job_assistant') &&
                      !_enabledModules.contains('astro_calendar'))
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
          backgroundColor: iconColor.withValues(alpha: 0.1),
          child: Icon(icon, color: iconColor),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        value: _notifPrefs[key] ?? true,
        onChanged: (val) => _saveNotificationPreference(key, val),
        activeThumbColor: iconColor,
      ),
    );
  }
}
