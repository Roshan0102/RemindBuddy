
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../services/storage_service.dart';
import 'add_task_screen.dart';
import '../models/calendar_reminder.dart';

import '../widgets/buddy_widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  final StorageService _storage = StorageService();

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Calendar'),
        actions: [
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _storage.getIncomingBuddyRequestsStream(),
            builder: (context, snapshot) {
              final requests = snapshot.data ?? [];
              final hasRequests = requests.isNotEmpty;
              return IconButton(
                icon: hasRequests
                    ? Badge(
                        label: Text(requests.length.toString()),
                        child: const Icon(Icons.people_outline),
                      )
                    : const Icon(Icons.people_outline),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    builder: (context) => BuddyRequestsSheet(),
                  );
                },
                tooltip: 'Buddy Link Requests',
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.person_add_alt_1),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => const BuddySelectionDialog(),
              );
            },
            tooltip: 'Link a Buddy',
          ),
        ],
      ),
      body: StreamBuilder<List<CalendarReminder>>(
        stream: _storage.getAllCalendarRemindersStream(),
        builder: (context, allSnapshot) {
          final allReminders = allSnapshot.data ?? [];
          
          return Column(
            children: [
              Card(
                margin: const EdgeInsets.all(8.0),
                elevation: 2,
                child: TableCalendar(
                  firstDay: DateTime.utc(2020, 1, 1),
                  lastDay: DateTime.utc(2030, 12, 31),
                  focusedDay: _focusedDay,
                  rowHeight: 42, // Reduced height
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  eventLoader: (day) {
                    final dateStr = DateFormat('yyyy-MM-dd').format(day);
                    final dayReminders = allReminders.where((r) => r.date == dateStr && r.status == 'scheduled').toList();
                    return GroupedCalendarReminder.groupList(dayReminders);
                  },
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                    });
                  },
                  calendarStyle: CalendarStyle(
                    markerDecoration: const BoxDecoration(
                      color: Colors.orange, // Orange dot for pending tasks
                      shape: BoxShape.circle,
                    ),
                    markerSize: 6,
                    markersAlignment: Alignment.bottomCenter,
                    todayDecoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    selectedDecoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  headerStyle: const HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                    titleTextStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    headerPadding: EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
              ),
              const Divider(),
              Expanded(
                child: _buildReminderList(),
              ),
            ],
          );
        }
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AddTaskScreen(selectedDate: _selectedDay),
            ),
          );
          if (result == true) {
            setState(() {});
          }
        },
        label: const Text('Add Reminder'),
        icon: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildReminderList() {
    if (_selectedDay == null) return const Center(child: Text('Select a day'));

    final String dateStr = DateFormat('yyyy-MM-dd').format(_selectedDay!);

    return StreamBuilder<List<CalendarReminder>>(
      stream: _storage.getCalendarRemindersStream(dateStr),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        
        final rawReminders = snapshot.data ?? [];
        final groupedReminders = GroupedCalendarReminder.groupList(rawReminders);
        if (groupedReminders.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.event_available, size: 64, color: Colors.grey.withValues(alpha: 0.5)),
                const SizedBox(height: 16),
                const Text('No reminders for this day', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        final isDarkMode = Theme.of(context).brightness == Brightness.dark;

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 80),
          itemCount: groupedReminders.length,
          itemBuilder: (context, index) {
            final grouped = groupedReminders[index];
            final isCompleted = (grouped.status == 'completed');
            final primaryId = grouped.primaryReminder.id ?? index.toString();

            return Dismissible(
              key: Key(primaryId),
              direction: DismissDirection.horizontal,
              background: Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 20.0),
                color: Colors.red,
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              secondaryBackground: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20.0),
                color: Colors.red,
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              confirmDismiss: (direction) async {
                return await _confirmDeleteGroup(grouped, silent: true);
              },
              child: Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: isCompleted
                    ? (isDarkMode ? Colors.green.withValues(alpha: 0.15) : Colors.green.shade50)
                    : null,
                child: ListTile(
                  leading: InkWell(
                    onTap: () => _toggleGroupStatus(grouped),
                    child: _buildStatusIcon(grouped.status),
                  ),
                  title: Text(
                    grouped.title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      decoration: isCompleted ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (grouped.description.isNotEmpty) Text(grouped.description),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('Time: ${grouped.time}', style: TextStyle(color: Colors.blue.shade700, fontSize: 12)),
                          ...grouped.recipientUsernames.map((userLabel) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: userLabel.startsWith('from') ? Colors.purple.shade50 : (userLabel == 'Myself' ? Colors.blue.shade50 : Colors.orange.shade50),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              userLabel,
                              style: TextStyle(
                                color: userLabel.startsWith('from') ? Colors.purple.shade800 : (userLabel == 'Myself' ? Colors.blue.shade800 : Colors.orange.shade800),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )),
                        ],
                      ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, color: Colors.blueAccent),
                        tooltip: 'Edit Reminder',
                        onPressed: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => AddTaskScreen(
                                selectedDate: _selectedDay,
                                existingReminder: grouped.primaryReminder,
                              ),
                            ),
                          );
                          if (result == true) {
                            setState(() {});
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        tooltip: 'Delete Reminder',
                        onPressed: () => _confirmDeleteGroup(grouped, silent: false),
                      ),
                    ],
                  ),
                  isThreeLine: true,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatusIcon(String status) {
    switch (status) {
      case 'scheduled':
        return const Icon(Icons.schedule, color: Colors.orange);
      case 'completed':
        return const Icon(Icons.check_circle, color: Colors.green);
      case 'expired':
        return const Icon(Icons.history, color: Colors.grey);
      case 'error':
        return const Icon(Icons.error_outline, color: Colors.red);
      default:
        return const Icon(Icons.help_outline);
    }
  }

  Future<void> _toggleGroupStatus(GroupedCalendarReminder grouped) async {
    final newStatus = (grouped.status == 'completed') ? 'scheduled' : 'completed';
    for (final r in grouped.originalReminders) {
      final updated = r.copyWith(status: newStatus);
      await _storage.updateCalendarReminder(updated);
    }
    if (mounted) setState(() {});
  }

  Future<bool> _confirmDeleteGroup(GroupedCalendarReminder grouped, {bool silent = false}) async {
    bool? result = silent;
    
    if (!silent) {
      result = await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Reminder?'),
          content: const Text('This will delete the reminder for all associated recipients.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(context, true), 
              child: const Text('Delete', style: TextStyle(color: Colors.red))
            ),
          ],
        ),
      );
    }

    if (result == true) {
      try {
        for (final r in grouped.originalReminders) {
          if (r.id != null) {
            await _storage.deleteCalendarReminder(r.id!);
          }
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Reminder deleted')),
          );
        }
        return true;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e')),
          );
        }
        return false;
      }
    }
    return false;
  }
}
