
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../models/daily_reminder.dart';
import '../services/storage_service.dart';
import 'package:google_fonts/google_fonts.dart';

class DailyRemindersScreen extends StatefulWidget {
  const DailyRemindersScreen({super.key});

  @override
  State<DailyRemindersScreen> createState() => _DailyRemindersScreenState();
}

class _DailyRemindersScreenState extends State<DailyRemindersScreen> {
  final StorageService _storageService = StorageService();

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
    bool snoozeEnabled = existingReminder?.snoozeEnabled ?? false;
    int snoozeIntervalMinutes = existingReminder?.snoozeIntervalMinutes ?? 15;
    int maxSnoozeCount = existingReminder?.maxSnoozeCount ?? 3;
    bool isSaving = false;

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
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Enable Snooze'),
                  subtitle: const Text('Remind again if not marked done'),
                  value: snoozeEnabled,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) {
                    setDialogState(() {
                      snoozeEnabled = val;
                    });
                  },
                ),
                if (snoozeEnabled) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          decoration: const InputDecoration(
                            labelText: 'Interval',
                            border: OutlineInputBorder(),
                          ),
                          value: snoozeIntervalMinutes,
                          items: [5, 10, 15, 30, 45, 60].map((mins) {
                            return DropdownMenuItem<int>(
                              value: mins,
                              child: Text('$mins mins'),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() {
                                snoozeIntervalMinutes = val;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          decoration: const InputDecoration(
                            labelText: 'Max Repeats',
                            border: OutlineInputBorder(),
                          ),
                          value: maxSnoozeCount,
                          items: [1, 2, 3, 5, 10].map((count) {
                            return DropdownMenuItem<int>(
                              value: count,
                              child: Text('$count times'),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() {
                                maxSnoozeCount = val;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            isSaving 
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : ElevatedButton(
                  onPressed: () async {
                    if (titleController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a title')),
                      );
                      return;
                    }

                    setDialogState(() => isSaving = true);
                    try {
                      final timeStr = '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';
                      
                      final reminder = existingReminder != null
                          ? existingReminder.copyWith(
                              title: titleController.text,
                              description: descriptionController.text,
                              time: timeStr,
                              isAnnoying: isAnnoying,
                              snoozeEnabled: snoozeEnabled,
                              snoozeIntervalMinutes: snoozeIntervalMinutes,
                              maxSnoozeCount: maxSnoozeCount,
                            )
                          : DailyReminder(
                              title: titleController.text,
                              description: descriptionController.text,
                              time: timeStr,
                              isActive: true,
                              isAnnoying: isAnnoying,
                              snoozeEnabled: snoozeEnabled,
                              snoozeIntervalMinutes: snoozeIntervalMinutes,
                              maxSnoozeCount: maxSnoozeCount,
                            );

                      if (existingReminder == null) {
                        await _storageService.insertDailyReminder(reminder);
                      } else {
                        await _storageService.updateDailyReminder(reminder);
                      }

                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Reminder saved')),
                        );
                      }
                    } catch (e) {
                      setDialogState(() => isSaving = false);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  child: const Text('Save'),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleReminder(DailyReminder reminder) async {
    final newState = !reminder.isActive;
    await _storageService.toggleDailyReminderActive(reminder.id!, newState);
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
      await _storageService.deleteDailyReminder(reminder.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reminder deleted')),
        );
      }
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
      body: StreamBuilder<List<DailyReminder>>(
        stream: _storageService.getDailyRemindersStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          final reminders = snapshot.data ?? [];
          
          if (reminders.isEmpty) {
            return Center(
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
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.only(left: 8, right: 8, top: 8, bottom: 88),
            itemCount: reminders.length,
            itemBuilder: (context, index) {
              final reminder = reminders[index];
              final now = DateTime.now();
              final todayDateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
              final isCompletedToday = reminder.lastCompletedDate == todayDateStr;

              return Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isCompletedToday
                        ? Colors.green
                        : (reminder.isActive
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey),
                    child: Icon(
                      isCompletedToday ? Icons.check : Icons.alarm,
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
                          if (reminder.snoozeEnabled) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Snooze: ${reminder.snoozeIntervalMinutes}m, Max ${reminder.maxSnoozeCount}x',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (isCompletedToday) ...[
                        const SizedBox(height: 4),
                        const Text(
                          'Completed for today',
                          style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (reminder.isActive)
                        IconButton(
                          icon: Icon(
                            isCompletedToday ? Icons.check_box : Icons.check_box_outline_blank,
                            color: isCompletedToday ? Colors.green : null,
                          ),
                          tooltip: isCompletedToday ? 'Mark incomplete for today' : 'Mark done for today',
                          onPressed: () async {
                            if (isCompletedToday) {
                              await _storageService.updateDailyReminder(reminder.copyWith(
                                lastCompletedDate: '',
                                currentSnoozeCount: 0,
                              ));
                            } else {
                              await _storageService.updateDailyReminder(reminder.copyWith(
                                lastCompletedDate: todayDateStr,
                                currentSnoozeCount: 0,
                              ));
                            }
                          },
                        ),
                      Switch(
                        value: reminder.isActive,
                        onChanged: (_) => _toggleReminder(reminder),
                      ),
                      PopupMenuButton(
                        onSelected: (value) {
                          if (value == 'edit') {
                            _showAddReminderDialog(reminder);
                          } else if (value == 'delete') {
                            _deleteReminder(reminder);
                          }
                        },
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
                      ),
                    ],
                  ),
                ),
              );
            },
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
      final minute = parts[parts.length - 1];
      final period = hour >= 12 ? 'PM' : 'AM';
      final hour12 = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$hour12:$minute $period';
    }
  }
