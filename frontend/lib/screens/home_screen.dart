import 'dart:async';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../models/task.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/notification_service.dart';
import '../services/log_service.dart';
import 'add_task_screen.dart';

import 'package:home_widget/home_widget.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // ... existing variables ...
  
  // Update Widget Data
  Future<void> _updateWidget() async {
    try {
      // Save data to SharedPreferences for the widget to read
      // Note: This requires the widget to be set up natively to read this data.
      // Since we can't easily edit native XML layouts without errors, we will just
      // prepare the data side here.
      // await HomeWidget.saveWidgetData<String>('title', 'RemindBuddy Tasks');
      // await HomeWidget.updateWidget(name: 'AppWidgetProvider');
    } catch (e) {
      print('Error updating widget: $e');
    }
  }
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  List<Task> _selectedTasks = [];
  
  final ApiService _apiService = ApiService();
  final StorageService _storageService = StorageService();
  final NotificationService _notificationService = NotificationService();
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _syncTasks(); // Initial sync
    
    // Periodic sync every hour (while app is in foreground)
    _syncTimer = Timer.periodic(const Duration(hours: 1), (timer) {
      _syncTasks();
    });
  }

  Widget _buildBuddyMascot() {
    int taskCount = _selectedTasks.length;
    IconData buddyIcon;
    Color buddyColor;

    if (taskCount == 0) {
      buddyIcon = Icons.sentiment_satisfied_alt; // Happy/Relaxed
      buddyColor = Colors.green;
    } else if (taskCount < 3) {
      buddyIcon = Icons.sentiment_neutral; // Neutral
      buddyColor = Colors.orange;
    } else {
      buddyIcon = Icons.sentiment_very_dissatisfied; // Stressed/Busy
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

  String _getBuddyMessage() {
    int taskCount = _selectedTasks.length;
    if (taskCount == 0) return "All clear! Relax time. 🌿";
    if (taskCount < 3) return "You got this! 💪";
    return "Busy day ahead! 🔥";
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _syncTasks() async {
    print('Syncing tasks...');
    // 1. Fetch from API
    List<Task> serverTasks = await _apiService.getTasks();
    
    if (serverTasks.isNotEmpty) {
      // 2. Store locally and schedule notifications
      for (var task in serverTasks) {
        await _storageService.insertTask(task);
        await _notificationService.scheduleTaskNotification(task);
      }
    }

    // 3. Clear old tasks - DISABLED to keep history
    // final String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    // await _storageService.clearOldTasks(today);

    // 4. Refresh UI
    _loadTasksForDay(_selectedDay!);
  }

  Future<void> _loadTasksForDay(DateTime day) async {
    final String dateStr = DateFormat('yyyy-MM-dd').format(day);
    List<Task> tasks = await _storageService.getTasksForDate(dateStr);
    setState(() {
      _selectedTasks = tasks;
    });
  }

  // Helper method to get tasks for a specific day (synchronous, returns current state)
  List<Task> _getTasksForDay(DateTime day) {
    // This returns the currently loaded tasks if the day matches
    if (_selectedDay != null && isSameDay(_selectedDay, day)) {
      return _selectedTasks;
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
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
                _loadTasksForDay(selectedDay);
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
                _buildBuddyMascot(),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getBuddyMessage(),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      '${_selectedTasks.length} tasks for today',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _selectedTasks.isEmpty
                ? const Center(child: Text('No tasks for this day'))
                : ListView.builder(
                    itemCount: _selectedTasks.length,
                    itemBuilder: (context, index) {
                      final task = _selectedTasks[index];
                      return Dismissible(
                        key: Key(task.id.toString()),
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20.0),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        direction: DismissDirection.endToStart,
                        onDismissed: (direction) async {
                          // 1. Remove from UI immediately
                          final deletedTask = task;
                          setState(() {
                            _selectedTasks.removeAt(index);
                          });

                          // 2. Delete from Local Storage & Cancel Notification
                          await _storageService.deleteTask(deletedTask.id!);
                          await _notificationService.cancelNotification(deletedTask.id!);

                          // 3. Delete from Server (Background)
                          try {
                            await _apiService.deleteTask(deletedTask.id!);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Task deleted')),
                            );
                            // Do NOT call _syncTasks() immediately here.
                            // The server delete is async. If we sync too fast, we might fetch the deleted task back.
                            // Since we already removed it from UI and Local DB, we are good.
                          } catch (e) {
                            LogService().error('Failed to delete from server', e);
                            // Optional: Re-add to UI if server delete fails?
                          }
                        },
                        child: ListTile(
                          title: Text(task.title),
                          subtitle: Text('${task.time} - ${task.description}'),
                          trailing: task.repeat != 'none' ? const Icon(Icons.repeat) : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
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
                _syncTasks(); // Refresh after adding
              }
            },
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
