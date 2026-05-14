import 'package:flutter/material.dart';
import '../services/storage_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final StorageService _storage = StorageService();
  List<String> _enabledModules = [];
  bool _isLoading = true;

  final List<Map<String, dynamic>> _allModules = [
    {'id': 'gold', 'label': 'Gold Rates', 'icon': Icons.monetization_on},
    {'id': 'reminders', 'label': 'Calendar Reminders', 'icon': Icons.calendar_today},
    {'id': 'notes', 'label': 'Aesthetic Notes', 'icon': Icons.note_alt},
    {'id': 'shifts', 'label': 'My Shifts', 'icon': Icons.work_history},
    {'id': 'checklist', 'label': 'Checklist', 'icon': Icons.playlist_add_check},
  ];

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await _storage.getUserPreferences();
    if (mounted) {
      setState(() {
        _enabledModules = List<String>.from(prefs['enabledModules'] ?? []);
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleModule(String id, bool enabled) async {
    setState(() {
      if (enabled) {
        _enabledModules.add(id);
      } else {
        // Prevent disabling all modules
        if (_enabledModules.length > 1) {
          _enabledModules.remove(id);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('At least one module must be enabled')),
          );
          return;
        }
      }
    });
    await _storage.updateUserPreferences(_enabledModules);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customize App'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Choose which features you want to see in your app. Changes are saved automatically.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _allModules.length,
                    itemBuilder: (context, index) {
                      final module = _allModules[index];
                      final isEnabled = _enabledModules.contains(module['id']);

                      return SwitchListTile(
                        title: Text(module['label'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        secondary: Icon(module['icon'], color: isEnabled ? Theme.of(context).primaryColor : Colors.grey),
                        value: isEnabled,
                        onChanged: (val) => _toggleModule(module['id'], val),
                      );
                    },
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Text(
                    'Restart the app or return to Home to see changes.',
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
    );
  }
}
