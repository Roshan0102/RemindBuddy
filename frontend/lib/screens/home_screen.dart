
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../services/storage_service.dart';
import 'add_task_screen.dart';
import '../models/calendar_reminder.dart';

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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
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
                    return allReminders.where((r) => r.date == dateStr && r.status == 'scheduled').toList();
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
                      color: Theme.of(context).primaryColor.withOpacity(0.3),
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
        
        final reminders = snapshot.data ?? [];
        if (reminders.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.event_available, size: 64, color: Colors.grey.withOpacity(0.5)),
                const SizedBox(height: 16),
                const Text('No reminders for this day', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: reminders.length,
          itemBuilder: (context, index) {
            final reminder = reminders[index];
            return Dismissible(
              key: Key(reminder.id!),
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
                return await _confirmDelete(reminder.id!, silent: true);
              },
              onDismissed: (direction) {
                // Already handled in confirmDismiss with the actual delete call
              },
              child: Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: _buildStatusIcon(reminder.status),
                  title: Text(reminder.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(reminder.description),
                      const SizedBox(height: 4),
                      Text('Time: ${reminder.time}', style: TextStyle(color: Colors.blue.shade700, fontSize: 12)),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_left, color: Colors.grey),
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

  Future<bool> _confirmDelete(String id, {bool silent = false}) async {
    bool? result = silent;
    
    if (!silent) {
      result = await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Reminder?'),
          content: const Text('This will also cancel any scheduled notifications.'),
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
        await _storage.deleteCalendarReminder(id);
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
