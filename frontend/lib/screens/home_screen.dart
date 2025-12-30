import 'dart:async';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../models/task.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/notification_service.dart';
import 'add_task_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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

    // 3. Clear old tasks
    final String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await _storageService.clearOldTasks(today);

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RemindBuddy'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: _syncTasks,
          )
        ],
      ),
      body: Column(
        children: [
          TableCalendar(
            firstDay: DateTime.utc(2020, 10, 16),
            lastDay: DateTime.utc(2030, 3, 14),
            focusedDay: _focusedDay,
            calendarFormat: _calendarFormat,
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
          ),
          const SizedBox(height: 8.0),
          Expanded(
            child: _selectedTasks.isEmpty
                ? const Center(child: Text('No tasks for this day'))
                : ListView.builder(
                    itemCount: _selectedTasks.length,
                    itemBuilder: (context, index) {
                      final task = _selectedTasks[index];
                      return ListTile(
                        title: Text(task.title),
                        subtitle: Text('${task.time} - ${task.description}'),
                        trailing: task.repeat != 'none' ? const Icon(Icons.repeat) : null,
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
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
    );
  }
}
