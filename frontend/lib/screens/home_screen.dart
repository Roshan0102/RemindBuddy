
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../services/storage_service.dart';
import 'add_task_screen.dart';
import '../services/log_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  
  final StorageService _storageService = StorageService();

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
  }

  Widget _getStatusIcon(String status) {
    switch (status) {
      case 'scheduled': return const Icon(Icons.timer_outlined, color: Colors.blue, size: 20);
      case 'completed': return const Icon(Icons.check_circle, color: Colors.green, size: 20);
      case 'expired': return const Icon(Icons.history, color: Colors.grey, size: 20);
      case 'error': return const Icon(Icons.error_outline, color: Colors.red, size: 20);
      default: return const Icon(Icons.hourglass_empty, color: Colors.orange, size: 20);
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'scheduled': return Colors.blue;
      case 'completed': return Colors.green;
      case 'expired': return Colors.grey;
      case 'error': return Colors.red;
      default: return Colors.orange;
    }
  }

  Widget _buildBuddyMascot(int count) {
    IconData buddyIcon;
    Color buddyColor;

    if (count == 0) {
      buddyIcon = Icons.sentiment_satisfied_alt;
      buddyColor = Colors.green;
    } else if (count < 3) {
      buddyIcon = Icons.sentiment_neutral;
      buddyColor = Colors.orange;
    } else {
      buddyIcon = Icons.sentiment_very_dissatisfied;
      buddyColor = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: buddyColor.withOpacity(0.2),
        shape: BoxShape.circle,
      ),
      child: Icon(buddyIcon, size: 32, color: buddyColor),
    );
  }

  String _getBuddyMessage(int count) {
    if (count == 0) return "All clear! Relax time. 🌿";
    if (count < 3) return "You got this! 💪";
    return "Busy day ahead! 🔥";
  }

  @override
  Widget build(BuildContext context) {
    final String dateStr = DateFormat('yyyy-MM-dd').format(_selectedDay ?? _focusedDay);

    return Scaffold(
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _storageService.getCalendarRemindersStream(dateStr),
        builder: (context, snapshot) {
          final reminders = snapshot.data ?? [];
          final tasksCount = reminders.length;

          return Column(
            children: [
              TableCalendar(
                firstDay: DateTime.utc(2020, 10, 16),
                lastDay: DateTime.utc(2030, 3, 14),
                focusedDay: _focusedDay,
                calendarFormat: _calendarFormat,
                availableCalendarFormats: const {
                  CalendarFormat.month: 'Month',
                },
                selectedDayPredicate: (day) {
                  return isSameDay(_selectedDay, day);
                },
                onDaySelected: (selectedDay, focusedDay) {
                  if (!isSameDay(_selectedDay, selectedDay)) {
                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                    });
                  }
                },
                onFormatChanged: (format) {
                  if (_calendarFormat != format) {
                    setState(() {
                      _calendarFormat = format;
                    });
                  }
                },
                onPageChanged: (focusedDay) {
                  _focusedDay = focusedDay;
                },
                calendarStyle: CalendarStyle(
                  todayDecoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  selectedDecoration: const BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                  ),
                  markerDecoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                  outsideDaysVisible: false,
                ),
                headerStyle: const HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                  titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8.0),
              // Buddy Mascot Area
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildBuddyMascot(tasksCount),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getBuddyMessage(tasksCount),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          '$tasksCount reminders for today',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const Center(child: CircularProgressIndicator())
                    : reminders.isEmpty
                        ? const Center(child: Text('No reminders for this day'))
                        : ListView.builder(
                            itemCount: reminders.length,
                            itemBuilder: (context, index) {
                              final reminder = reminders[index];
                              final status = reminder['status'] ?? 'pending';
                              
                              return Dismissible(
                                key: Key(reminder['id'].toString()),
                                background: Container(
                                  color: Colors.red,
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20.0),
                                  child: const Icon(Icons.delete, color: Colors.white),
                                ),
                                direction: DismissDirection.endToStart,
                                onDismissed: (direction) async {
                                  await _storageService.deleteCalendarReminder(reminder['id'].toString());
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Reminder deleted')),
                                    );
                                  }
                                },
                                child: ListTile(
                                  leading: _getStatusIcon(status),
                                  title: Text(reminder['title']),
                                  subtitle: Text('${reminder['time']} - ${reminder['description']}'),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        status.toUpperCase(), 
                                        style: TextStyle(
                                          fontSize: 10, 
                                          color: _getStatusColor(status),
                                          fontWeight: FontWeight.bold
                                        )
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          );
        }
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'log_btn',
            mini: true,
            backgroundColor: Colors.grey,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LogScreen()),
              );
            },
            child: const Icon(Icons.bug_report),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'add_btn',
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AddTaskScreen(selectedDate: _selectedDay),
                ),
              );
              if (result == true) {
                // Refresh handled by stream
              }
            },
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
