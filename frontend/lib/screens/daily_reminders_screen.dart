import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../models/daily_reminder.dart';
import '../services/storage_service.dart';
import '../services/notification_service.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';

class DailyRemindersScreen extends StatefulWidget {
  const DailyRemindersScreen({super.key});

  @override
  State<DailyRemindersScreen> createState() => _DailyRemindersScreenState();
}

class _DailyRemindersScreenState extends State<DailyRemindersScreen> {
  final StorageService _storageService = StorageService();
  final NotificationService _notificationService = NotificationService();
  List<DailyReminder> _reminders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadReminders();
  }

  Future<void> _loadReminders() async {
    setState(() => _isLoading = true);
    final reminders = await _storageService.getDailyReminders();
    setState(() {
      _reminders = reminders;
      _isLoading = false;
    });
  }

  Future<void> _showAddReminderDialog([DailyReminder? existingReminder]) async {
    final titleController = TextEditingController(text: existingReminder?.title ?? '');
    final descriptionController = TextEditingController(text: existingReminder?.description ?? '');
    TimeOfDay selectedTime = existingReminder != null
        ? TimeOfDay(
            hour: int.parse(existingReminder.time.split(':')[0]),
            minute: int.parse(existingReminder.time.split(':')[1]),
          )
        : TimeOfDay.now();
    bool isAnnoying = existingReminder?.isAnnoying ?? false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existingReminder == null ? 'Add Daily Reminder' : 'Edit Daily Reminder'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('Time'),
                  subtitle: Text(selectedTime.format(context)),
                  trailing: const Icon(Icons.access_time),
                  onTap: () async {
                    showModalBottomSheet(
                      context: context,
                      builder: (BuildContext builder) {
                        return Container(
                          height: MediaQuery.of(context).size.height / 3,
                          color: Colors.white,
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  TextButton(
                                    child: const Text('Cancel'),
                                    onPressed: () => Navigator.of(context).pop(),
                                  ),
                                  TextButton(
                                    child: const Text('Done'),
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                      setDialogState(() {}); // Refresh dialog UI
                                    },
                                  ),
                                ],
                              ),
                              Expanded(
                                child: CupertinoDatePicker(
                                  mode: CupertinoDatePickerMode.time,
                                  initialDateTime: DateTime(
                                    DateTime.now().year,
                                    DateTime.now().month,
                                    DateTime.now().day,
                                    selectedTime.hour,
                                    selectedTime.minute,
                                  ),
                                  onDateTimeChanged: (DateTime newDateTime) {
                                    setDialogState(() {
                                      selectedTime = TimeOfDay.fromDateTime(newDateTime);
                                    });
                                  },
                                  use24hFormat: false,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
                SwitchListTile(
                  title: const Text('Annoying Mode'),
                  subtitle: const Text('Keeps reminding until you say YES'),
                  value: isAnnoying,
                  onChanged: (value) {
                    setDialogState(() {
                      isAnnoying = value;
                    });
                  },
                  secondary: const Icon(Icons.alarm_on, color: Colors.red),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (titleController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a title')),
                  );
                  return;
                }

                final timeStr = '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';
                
                final reminder = existingReminder != null
                    ? existingReminder.copyWith(
                        title: titleController.text,
                        description: descriptionController.text,
                        time: timeStr,
                        isAnnoying: isAnnoying,
                      )
                    : DailyReminder(
                        title: titleController.text,
                        description: descriptionController.text,
                        time: timeStr,
                        isActive: true,
                        isAnnoying: isAnnoying,
                      );

                if (existingReminder == null) {
                  final id = await _storageService.insertDailyReminder(reminder);
                  // Schedule notification for the new reminder
                  await _scheduleDailyReminder(reminder.copyWith(id: id));
                } else {
                  await _storageService.updateDailyReminder(reminder);
                  // Re-schedule notification
                  await _scheduleDailyReminder(reminder);
                }

                // Trigger sync
                try {
                  SyncService(AuthService().pb).syncDailyReminders();
                } catch (e) { print(e); }

                Navigator.pop(context);
                _loadReminders();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _scheduleDailyReminder(DailyReminder reminder) async {
    if (!reminder.isActive || reminder.id == null) return;

    // Cancel existing notification for this reminder
    await _notificationService.cancelNotification(reminder.id! + 100000); // Offset to avoid conflicts with tasks

    // Schedule new daily notification
    await _notificationService.scheduleDailyReminder(reminder);
  }

  Future<void> _toggleReminder(DailyReminder reminder) async {
    final newState = !reminder.isActive;
    await _storageService.toggleDailyReminderActive(reminder.id!, newState);
    
    if (newState) {
      // Re-enable: schedule notification
      await _scheduleDailyReminder(reminder.copyWith(isActive: true));
    } else {
      // Disable: cancel notification
      await _notificationService.cancelNotification(reminder.id! + 100000);
    }
    
    // Trigger sync
    try {
      SyncService(AuthService().pb).syncDailyReminders();
    } catch (e) { print(e); }
    
    _loadReminders();
  }

  Future<void> _deleteReminder(DailyReminder reminder) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Reminder'),
        content: Text('Are you sure you want to delete "${reminder.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _notificationService.cancelNotification(reminder.id! + 100000);
      await _storageService.deleteDailyReminder(reminder.id!);
      try {
        SyncService(AuthService().pb).syncDeletions();
      } catch (e) { print(e); }
      _loadReminders();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Daily Reminders',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _reminders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.alarm_add, size: 80, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No daily reminders yet',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap + to create your first daily reminder',
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _reminders.length,
                  itemBuilder: (context, index) {
                    final reminder = _reminders[index];
                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: reminder.isActive
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey,
                          child: Icon(
                            reminder.isAnnoying ? Icons.alarm_on : Icons.alarm,
                            color: Colors.white,
                          ),
                        ),
                        title: Text(
                          reminder.title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            decoration: reminder.isActive ? null : TextDecoration.lineThrough,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (reminder.description.isNotEmpty)
                              Text(reminder.description),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Text(
                                  _formatTime(reminder.time),
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (reminder.isAnnoying) ...[
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.red[100],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Nag Mode',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.red[900],
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: reminder.isActive,
                              onChanged: (_) => _toggleReminder(reminder),
                            ),
                            PopupMenuButton(
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit),
                                      SizedBox(width: 8),
                                      Text('Edit'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text('Delete', style: TextStyle(color: Colors.red)),
                                    ],
                                  ),
                                ),
                              ],
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _showAddReminderDialog(reminder);
                                } else if (value == 'delete') {
                                  _deleteReminder(reminder);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddReminderDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Add Reminder'),
      ),
    );
  }

  String _formatTime(String time24) {
    final parts = time24.split(':');
    final hour = int.parse(parts[0]);
    final minute = parts[1];
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$hour12:$minute $period';
  }
}

// Extension to create a copy with modified fields
